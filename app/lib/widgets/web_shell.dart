import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import 'desktop_shell_scope.dart';

class WebShell extends StatefulWidget {
  final Widget child;
  final String currentRoute;
  final ApiClient api;
  final StorageService storage;

  const WebShell({
    super.key,
    required this.child,
    required this.currentRoute,
    required this.api,
    required this.storage,
  });

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  String? _role;

  @override
  void initState() {
    super.initState();
    widget.storage.getRole().then((r) {
      if (mounted) setState(() => _role = r);
    });
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (_) {}
    await widget.storage.clear();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return DesktopShellScope(
      isDesktop: isDesktop,
      child: isDesktop
          ? Row(
              children: [
                SizedBox(
                  width: 220,
                  child: _Sidebar(
                    currentRoute: widget.currentRoute,
                    role: _role,
                    onLogout: _logout,
                    onNavigate: (route) => context.go(route),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: widget.child),
              ],
            )
          : widget.child,
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String currentRoute;
  final String? role;
  final VoidCallback onLogout;
  final void Function(String route) onNavigate;

  const _Sidebar({
    required this.currentRoute,
    required this.role,
    required this.onLogout,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primary;
    const fg = Colors.black;
    return Material(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  'assets/images/cocamatic-logo.png',
                  height: 44,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                ),
                const SizedBox(height: 4),
                Text(
                  'Sistema de revisiones',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: fg.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavItem(
                    icon: Icons.list_alt,
                    label: 'Máquinas',
                    selected: currentRoute == '/machines',
                    onTap: () => onNavigate('/machines'),
                  ),
                  _NavItem(
                    icon: Icons.history,
                    label: 'Histórico',
                    selected: currentRoute == '/history',
                    onTap: () => onNavigate('/history'),
                  ),
                  _NavItem(
                    icon: Icons.assessment,
                    label: 'Reportes',
                    selected: currentRoute == '/reports',
                    onTap: () => onNavigate('/reports'),
                  ),
                  _NavItem(
                    icon: Icons.bar_chart,
                    label: 'Estadísticas',
                    selected: currentRoute == '/stats',
                    onTap: () => onNavigate('/stats'),
                  ),
                  _NavItem(
                    icon: Icons.build,
                    label: 'Repuestos',
                    selected: currentRoute == '/repuestos',
                    onTap: () => onNavigate('/repuestos'),
                  ),
                  _NavItem(
                    icon: Icons.report_problem,
                    label: 'Incidencias',
                    selected: currentRoute == '/incidencias',
                    onTap: () => onNavigate('/incidencias'),
                  ),
                  if (role == 'admin')
                    _NavItem(
                      icon: Icons.settings,
                      label: 'Admin',
                      selected: currentRoute == '/admin',
                      onTap: () => onNavigate('/admin'),
                    ),
                ],
              ),
            ),
          ),
          _NavItem(
            icon: Icons.logout,
            label: 'Cerrar sesión',
            selected: false,
            onTap: onLogout,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const fg = Colors.black;
    return ListTile(
      selected: selected,
      selectedTileColor: fg.withValues(alpha: 0.12),
      leading: Icon(icon, color: selected ? fg : fg.withValues(alpha: 0.7)),
      title: Text(
        label,
        style: TextStyle(color: selected ? fg : fg.withValues(alpha: 0.7)),
      ),
      onTap: onTap,
    );
  }
}
