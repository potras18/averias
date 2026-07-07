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
  if (location.startsWith('/admin')) return '/admin';
  if (location.startsWith('/scan')) return '/scan';
  return '/machines';
}

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
          builder: (_, state) => MachineListScreen(
            api: _api,
            storage: _storage,
            preselectedId: state.uri.queryParameters['selected'],
          ),
        ),
        GoRoute(
          path: '/machines/:id',
          builder: (_, state) => MachineDetailScreen(
            api: _api,
            storage: _storage,
            machineId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/history',
          builder: (_, state) => MachineHistoryScreen(
            api: _api,
            preselectedId: state.uri.queryParameters['selected'],
          ),
        ),
        GoRoute(
          path: '/history/:id',
          builder: (_, state) => MachineHistoryDetailScreen(
            api: _api,
            machineId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/machines/:id/inspect',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return InspectionFormScreen(
              api: _api,
              machineId: state.pathParameters['id']!,
              hasRedemptionTickets: extra['hasRedemptionTickets'] as bool? ?? false,
              inspection: extra['inspection'] as dynamic,
            );
          },
        ),
        GoRoute(path: '/scan', builder: (_, __) => QrScannerScreen(api: _api)),
        GoRoute(path: '/reports', builder: (_, __) => ReportScreen(api: _api)),
        GoRoute(path: '/stats', builder: (_, __) => StatsScreen(api: _api)),
        GoRoute(
          path: '/admin',
          builder: (_, __) => AdminScreen(api: _api, storage: _storage),
        ),
        GoRoute(
          path: '/repuestos',
          builder: (_, __) => SparePartsScreen(api: _api, storage: _storage),
        ),
        GoRoute(
          path: '/repuestos/new',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return SparePartFormScreen(
              api: _api,
              preselectedMachineId: extra['machineId'] as String?,
            );
          },
        ),
        GoRoute(
          path: '/repuestos/:id/edit',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return SparePartFormScreen(
              api: _api,
              sparePart: extra['sparePart'] as SparePart?,
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
