import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/machine_list_screen.dart';
import 'screens/machine_detail_screen.dart';
import 'screens/machine_history_screen.dart';
import 'screens/machine_history_detail_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/report_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/spare_parts_screen.dart';
import 'screens/spare_part_form_screen.dart';
import 'screens/incidencia_form_screen.dart';
import 'screens/incidencias_screen.dart';
import 'models/spare_part.dart';
import 'services/storage_service.dart';
import 'services/api_client.dart';
import 'widgets/web_shell.dart';

final _storage = StorageService();
final _api = ApiClient(_storage);

/// Maps the current location to the sidebar section it belongs to, so detail
/// and form sub-routes keep their parent nav item highlighted.
String _sectionFor(String location) {
  if (location.startsWith('/history')) return '/history';
  if (location.startsWith('/reports')) return '/reports';
  if (location.startsWith('/stats')) return '/stats';
  if (location.startsWith('/repuestos')) return '/repuestos';
  if (location.startsWith('/incidencias')) return '/incidencias';
  if (location.startsWith('/admin')) return '/admin';
  if (location.startsWith('/scan')) return '/scan';
  return '/machines';
}

/// Content swaps with no transition animation — only the inner content changes,
/// the shell stays put.
Page<void> _noTransition(GoRouterState state, Widget child) =>
    NoTransitionPage(key: state.pageKey, child: child);

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final token = await _storage.getAccessToken();
    final loc = state.matchedLocation;
    final atLogin = loc.startsWith('/login');
    if (token == null) return atLogin ? null : '/login';
    // Client (reportes) users are confined to the single report page.
    final role = await _storage.getRole();
    if (role == 'reportes') return loc == '/incidencia' ? null : '/incidencia';
    // Staff never sit on the login or client page while authenticated.
    if (atLogin || loc == '/incidencia') return '/machines';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => LoginScreen(api: _api, storage: _storage)),
    GoRoute(path: '/incidencia', builder: (_, __) => IncidenciaFormScreen(api: _api, storage: _storage)),
    // The shell (desktop sidebar + content) is built once and persists across
    // navigations, so only the content swaps — the menu stays fixed.
    ShellRoute(
      builder: (context, state, child) => WebShell(
        currentRoute: _sectionFor(state.uri.path),
        api: _api,
        storage: _storage,
        child: child,
      ),
      routes: [
        GoRoute(
          path: '/machines',
          pageBuilder: (_, state) => _noTransition(
            state,
            MachineListScreen(
              api: _api,
              storage: _storage,
              preselectedId: state.uri.queryParameters['selected'],
            ),
          ),
        ),
        GoRoute(
          path: '/machines/:id',
          pageBuilder: (_, state) => _noTransition(
            state,
            MachineDetailScreen(
              api: _api,
              storage: _storage,
              machineId: state.pathParameters['id']!,
            ),
          ),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (_, state) => _noTransition(
            state,
            MachineHistoryScreen(
              api: _api,
              storage: _storage,
              preselectedId: state.uri.queryParameters['selected'],
            ),
          ),
        ),
        GoRoute(
          path: '/history/:id',
          pageBuilder: (_, state) => _noTransition(
            state,
            MachineHistoryDetailScreen(
              api: _api,
              storage: _storage,
              machineId: state.pathParameters['id']!,
            ),
          ),
        ),
        GoRoute(
          path: '/machines/:id/inspect',
          pageBuilder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return _noTransition(
              state,
              InspectionFormScreen(
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
          pageBuilder: (_, state) => _noTransition(state, QrScannerScreen(api: _api)),
        ),
        GoRoute(
          path: '/reports',
          pageBuilder: (_, state) => _noTransition(state, ReportScreen(api: _api)),
        ),
        GoRoute(
          path: '/stats',
          pageBuilder: (_, state) => _noTransition(state, StatsScreen(api: _api)),
        ),
        GoRoute(
          path: '/admin',
          pageBuilder: (_, state) =>
              _noTransition(state, AdminScreen(api: _api, storage: _storage)),
        ),
        GoRoute(
          path: '/repuestos',
          pageBuilder: (_, state) =>
              _noTransition(state, SparePartsScreen(api: _api, storage: _storage)),
        ),
        GoRoute(
          path: '/incidencias',
          pageBuilder: (_, state) => _noTransition(state, IncidenciasScreen(api: _api, storage: _storage)),
        ),
        GoRoute(
          path: '/repuestos/new',
          pageBuilder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return _noTransition(
              state,
              SparePartFormScreen(
                api: _api,
                preselectedMachineId: extra['machineId'] as String?,
              ),
            );
          },
        ),
        GoRoute(
          path: '/repuestos/:id/edit',
          pageBuilder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return _noTransition(
              state,
              SparePartFormScreen(
                api: _api,
                sparePart: extra['sparePart'] as SparePart?,
              ),
            );
          },
        ),
      ],
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
      theme: cocamaticTheme(),
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
