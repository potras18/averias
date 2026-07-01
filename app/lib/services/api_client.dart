import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/location.dart';
import '../models/stats.dart';
import '../models/user.dart';
import '../models/settings.dart';
import '../models/spare_part.dart';
import 'storage_service.dart';

class ApiClient {
  static const String _baseUrl =
      String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  late final Dio _dio;
  final StorageService _storage;
  void Function()? onUnauthorized;
  bool _isRefreshing = false;

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
      onError: (error, handler) async {
        final is401 = error.response?.statusCode == 401;
        final isRefreshCall = error.requestOptions.path.contains('/auth/refresh');
        if (is401 && !isRefreshCall && !_isRefreshing) {
          _isRefreshing = true;
          try {
            final refreshToken = await _storage.getRefreshToken();
            if (refreshToken != null) {
              final res = await _dio.post('/auth/refresh',
                  data: {'refreshToken': refreshToken});
              final newToken = res.data['accessToken'] as String;
              final newRefreshToken = res.data['refreshToken'] as String;
              await _storage.setTokens(
                  accessToken: newToken, refreshToken: newRefreshToken);
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newToken';
              final retried = await _dio.fetch(opts);
              return handler.resolve(retried);
            }
          } catch (_) {
            // refresh failed — fall through to logout
          } finally {
            _isRefreshing = false;
          }
          await _storage.clear();
          onUnauthorized?.call();
        }
        handler.next(error);
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
  Future<List<Machine>> getMachines({
    String? locationId,
    bool includeInactive = false,
    DateTime? inspectionDate,
  }) async {
    final res = await _dio.get('/machines', queryParameters: {
      if (locationId != null) 'location_id': locationId,
      if (includeInactive) 'include_inactive': 'true',
      if (inspectionDate != null)
        'inspection_date': inspectionDate.toIso8601String().substring(0, 10),
    });
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

  Future<Machine> createMachineAdmin({
    required String name,
    String? locationId,
    bool hasRedemptionTickets = false,
  }) async {
    final res = await _dio.post('/machines', data: {
      'name': name,
      if (locationId != null) 'location_id': locationId,
      'has_redemption_tickets': hasRedemptionTickets,
    });
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Machine> updateMachine(
    String id, {
    required String name,
    String? locationId,
    required bool hasRedemptionTickets,
  }) async {
    final res = await _dio.put('/machines/$id', data: {
      'name': name,
      'location_id': locationId,
      'has_redemption_tickets': hasRedemptionTickets,
    });
    return Machine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> decommissionMachine(String id) async {
    await _dio.patch('/machines/$id/decommission');
  }

  Future<Uint8List> getMachineQrPdf(String id) async {
    final res = await _dio.get(
      '/machines/$id/qr/pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data as List<int>);
  }

  // Inspections
  Future<Inspection> createInspection(Map<String, dynamic> data) async {
    final res = await _dio.post('/inspections', data: data);
    return Inspection.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Inspection> updateInspection(String id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/inspections/$id', data: data);
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
    String? from,
    String? to,
    String? locationId,
  }) async {
    await _dio.post('/reports/email', data: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    });
  }

  // Stats
  Future<StatsResult> getStats({String? from, String? to, String? locationId}) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    };
    final res = await _dio.get(
      '/stats',
      queryParameters: params.isNotEmpty ? params : null,
    );
    return StatsResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Uint8List> getStatsPdf({String? from, String? to, String? locationId}) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    };
    final res = await _dio.get(
      '/stats/pdf',
      queryParameters: params.isNotEmpty ? params : null,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data as List<int>);
  }

  Future<void> sendStatsByEmail({
    String? from,
    String? to,
    String? locationId,
  }) async {
    await _dio.post('/stats/email', data: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (locationId != null) 'location_id': locationId,
    });
  }

  // Settings
  Future<Settings> getSettings() async {
    final res = await _dio.get('/settings');
    return Settings.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Settings> updateSettings(Map<String, dynamic> body) async {
    final res = await _dio.put('/settings', data: body);
    return Settings.fromJson(res.data as Map<String, dynamic>);
  }

  // Admin — Locations
  Future<Location> createLocation({required String name, String? address}) async {
    final res = await _dio.post('/locations', data: {
      'name': name,
      if (address != null && address.isNotEmpty) 'address': address,
    });
    return Location.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Location> updateLocation(String id, {required String name, String? address}) async {
    final res = await _dio.put('/locations/$id', data: {
      'name': name,
      if (address != null && address.isNotEmpty) 'address': address,
    });
    return Location.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteLocation(String id) async {
    await _dio.delete('/locations/$id');
  }

  // Admin — Users
  Future<List<User>> getUsers({bool includeInactive = false}) async {
    final res = await _dio.get(
      '/users',
      queryParameters: includeInactive ? {'include_inactive': 'true'} : null,
    );
    return (res.data as List)
        .map((j) => User.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<User> createUser({
    required String name,
    required String email,
    required String role,
    required String password,
  }) async {
    final res = await _dio.post('/users', data: {
      'name': name,
      'email': email,
      'role': role,
      'password': password,
    });
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  Future<User> updateUser(
    String id, {
    String? name,
    String? email,
    String? password,
  }) async {
    final res = await _dio.patch('/users/$id', data: {
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (password != null && password.isNotEmpty) 'password': password,
    });
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  Future<User> updateUserRole(String id, String role) async {
    final res = await _dio.patch('/users/$id/role', data: {'role': role});
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  Future<User> deactivateUser(String id) async {
    final res = await _dio.patch('/users/$id/deactivate');
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  // Spare Parts
  Future<List<SparePart>> getSpareParts({String? machineId, String? status}) async {
    final res = await _dio.get('/repuestos', queryParameters: {
      if (machineId != null) 'machine_id': machineId,
      if (status != null) 'status': status,
    });
    return (res.data as List)
        .map((j) => SparePart.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<Inspection>> getInspections({required String machineId}) async {
    final res = await _dio.get('/inspections', queryParameters: {'machine_id': machineId});
    return (res.data as List).map((j) => Inspection.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<SparePart> createSparePart({
    required String machineId,
    required String description,
    required int quantity,
  }) async {
    final res = await _dio.post('/repuestos', data: {
      'machine_id': machineId,
      'description': description,
      'quantity': quantity,
    });
    return SparePart.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SparePart> updateSparePart(
    String id, {
    String? description,
    int? quantity,
    String? status,
  }) async {
    final res = await _dio.patch('/repuestos/$id', data: {
      if (description != null) 'description': description,
      if (quantity != null) 'quantity': quantity,
      if (status != null) 'status': status,
    });
    return SparePart.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteSparePart(String id) async {
    await _dio.delete('/repuestos/$id');
  }
}
