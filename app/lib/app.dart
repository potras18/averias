import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/machine_detail_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/report_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/spare_parts_screen.dart';
import 'screens/spare_part_form_screen.dart';
import 'models/spare_part.dart';
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
          storage: _storage,
          machineId: state.pathParameters['id']!,
        ),
      ),
    ),
    GoRoute(
      path: '/machines/:id/inspect',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return _shell(
          route: '/machines',
          child: InspectionFormScreen(
            api: _api,
            machineId: state.pathParameters['id']!,
            hasRedemptionTickets: extra['hasRedemptionTickets'] as bool? ?? false,
            inspection: extra['inspection'] as dynamic,
          ),
        );
      },
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
    GoRoute(
      path: '/repuestos',
      builder: (_, __) => _shell(
        route: '/repuestos',
        child: SparePartsScreen(api: _api, storage: _storage),
      ),
    ),
    GoRoute(
      path: '/repuestos/new',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return _shell(
          route: '/repuestos',
          child: SparePartFormScreen(
            api: _api,
            preselectedMachineId: extra['machineId'] as String?,
          ),
        );
      },
    ),
    GoRoute(
      path: '/repuestos/:id/edit',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return _shell(
          route: '/repuestos',
          child: SparePartFormScreen(
            api: _api,
            sparePart: extra['sparePart'] as SparePart?,
          ),
        );
      },
    ),
  ],
);

class AveApp extends StatefulWidget {
  const AveApp({super.key});

  @override
  State<AveApp> createState() => _AveAppState();
}

class _AveAppState extends State<AveApp> {
  @override
  void initState() {
    super.initState();
    _api.onUnauthorized = () {
      _router.go('/login');
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Cocamatic',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      routerConfig: _router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'),
        Locale('en'),
      ],
    );
  }
}
