// app/lib/screens/no_access_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/permissions_service.dart';
import '../services/storage_service.dart';

/// Safety-net screen shown when a staff user's role has zero `.view`
/// permissions granted (so there is no route left for `landingRoute()` to
/// send them to). Not gated by `_permissionForLocation` and not subject to
/// the login/`/incidencia` bounce-back rule in `app.dart`'s router redirect,
/// so it can render without immediately being redirected away again.
class NoAccessScreen extends StatelessWidget {
  final ApiClient api;
  final StorageService storage;

  const NoAccessScreen({super.key, required this.api, required this.storage});

  Future<void> _logout(BuildContext context) async {
    try {
      await api.logout();
    } catch (_) {}
    await storage.clear();
    PermissionsService.instance.reset();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Tu cuenta no tiene ningún permiso asignado. Contacta con un administrador.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _logout(context),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
