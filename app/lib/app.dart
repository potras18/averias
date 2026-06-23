import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/machine_detail_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/report_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/admin_screen.dart';
import 'services/storage_service.dart';
import 'services/api_client.dart';
import 'widgets/web_shell.dart';

final _storage = StorageService();
final _api = ApiClient(_storage);

WebShell _shell({required String route, required Widget child}) => WebShell(
      currentRoute: route,
      api: _api,
      storage: _storage,
      child: child,
    );

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
    GoRoute(
      path: '/machines',
      builder: (_, state) => _shell(
        route: '/machines',
        child: MachineListScreen(
          api: _api,
          storage: _storage,
          preselectedId: state.uri.queryParameters['selected'],
        ),
      ),
    ),
    GoRoute(
      path: '/machines/:id',
      builder: (_, state) => _shell(
        route: '/machines',
        child: MachineDetailScreen(
          api: _api,
          machineId: state.pathParameters['id']!,
        ),
      ),
    ),
    GoRoute(
      path: '/machines/:id/inspect',
      builder: (_, state) => _shell(
        route: '/machines',
        child: InspectionFormScreen(
          api: _api,
          machineId: state.pathParameters['id']!,
          hasRedemptionTickets: state.extra as bool? ?? false,
        ),
      ),
    ),
    GoRoute(
      path: '/scan',
      builder: (_, __) => _shell(route: '/scan', child: QrScannerScreen(api: _api)),
    ),
    GoRoute(
      path: '/reports',
      builder: (_, __) => _shell(route: '/reports', child: ReportScreen(api: _api)),
    ),
    GoRoute(
      path: '/stats',
      builder: (_, __) => _shell(route: '/stats', child: StatsScreen(api: _api)),
    ),
    GoRoute(
      path: '/admin',
      builder: (_, __) =>
          _shell(route: '/admin', child: AdminScreen(api: _api, storage: _storage)),
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
