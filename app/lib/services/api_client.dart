import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/location.dart';
import '../models/user.dart';
import 'storage_service.dart';

class ApiClient {
  static const String _baseUrl =
      String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  late final Dio _dio;
  final StorageService _storage;

  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.getAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  // Auth
  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    return res.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await _dio.post('/auth/logout');
  }

  // Locations
  Future<List<Location>> getLocations() async {
    final res = await _dio.get('/locations');
    return (res.data as List).map((j) => Location.fromJson(j as Map<String, dynamic>)).toList();
  }

  // Machines
  Future<List<Machine>> getMachines({String? locationId}) async {
    final res = await _dio.get('/machines',
        queryParameters: locationId != null ? {'location_id': locationId} : null);
    return (res.data as List).map((j) => Machine.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Machine> getMachineById(String id) async {
    final res = await _dio.get('/machines/$id');
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Machine> getMachineByQr(String code) async {
    final res = await _dio.get('/machines/qr/$code');
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Machine> createMachine(Map<String, dynamic> data) async {
    final res = await _dio.post('/machines', data: data);
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  // Inspections
  Future<Inspection> createInspection(Map<String, dynamic> data) async {
    final res = await _dio.post('/inspections', data: data);
    return Inspection.fromJson(res.data as Map<String, dynamic>);
  }

  // Reports
  Future<Uint8List> getReportPdf({String? from, String? to, String? locationId}) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    };
    final res = await _dio.get(
      '/reports/pdf',
      queryParameters: params.isNotEmpty ? params : null,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data as List<int>);
  }

  Future<void> sendReportByEmail({
    required List<String> emails,
    String? from,
    String? to,
    String? locationId,
  }) async {
    await _dio.post('/reports/email', data: {
      'emails': emails,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    });
  }
}
