import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/machine_detail_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/report_screen.dart';
import 'services/storage_service.dart';
import 'services/api_client.dart';

final _storage = StorageService();
final _api = ApiClient(_storage);

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final token = await _storage.getAccessToken();
    if (token == null && !state.matchedLocation.startsWith('/login')) {
      return '/login';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => LoginScreen(api: _api, storage: _storage)),
    GoRoute(path: '/machines', builder: (_, __) => MachineListScreen(api: _api)),
    GoRoute(
      path: '/machines/:id',
      builder: (_, state) => MachineDetailScreen(
        api: _api,
        machineId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/machines/:id/inspect',
      builder: (_, state) => InspectionFormScreen(
        api: _api,
        machineId: state.pathParameters['id']!,
        hasRedemptionTickets: state.extra as bool? ?? false,
      ),
    ),
    GoRoute(
      path: '/scan',
      builder: (_, __) => QrScannerScreen(api: _api),
    ),
    GoRoute(
      path: '/reports',
      builder: (_, __) => ReportScreen(api: _api),
    ),
  ],
);

class AveApp extends StatelessWidget {
  const AveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Averías',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      routerConfig: _router,
    );
  }
}
