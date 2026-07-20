import 'package:flutter/foundation.dart' show visibleForTesting;
import 'api_client.dart';
import 'storage_service.dart';

/// Session-wide permission resolver. Loaded once per login from
/// GET /role-permissions/me (the caller's own resolved permissions).
/// `admin` short-circuits to "allow all"; `reportes`
/// is handled separately by the router redirect. On a load failure we fall
/// back to the most restrictive built-in set (technician minus stats), never
/// failing open.
class PermissionsService {
  PermissionsService._();
  static final PermissionsService instance = PermissionsService._();

  ApiClient? _api;
  StorageService? _storage;
  String? _role;
  String? _loadedForRole;
  Map<String, bool> _perms = {};

  /// technician-minus-stats fallback (never fail open).
  static const Map<String, bool> fallbackNonAdmin = {
    'estadisticas.view': false,
    'informes.view': true,
    'incidencias.view': true,
    'incidencias.edit': true,
    'inspecciones.view': true,
    'inspecciones.edit': true,
    'maquinas.view': true,
    'maquinas.edit': false,
    'repuestos.view': true,
    'repuestos.edit': false,
    'admin.view': false,
  };

  void configure(ApiClient api, StorageService storage) {
    _api = api;
    _storage = storage;
  }

  Future<void> ensureLoaded() async {
    final storage = _storage;
    if (storage == null) return;
    final role = await storage.getRole();
    if (_loadedForRole == role && role != null) return;
    await _load(role);
  }

  Future<void> _load(String? role) async {
    _role = role;
    _loadedForRole = role;
    if (role == null || role == 'admin' || role == 'reportes') {
      _perms = {};
      return;
    }
    try {
      _perms = await _api!.getMyPermissions();
    } catch (_) {
      _perms = Map.of(fallbackNonAdmin);
    }
  }

  bool can(String key) {
    if (_role == 'admin') return true;
    return _perms[key] ?? false;
  }

  /// First route the current user is allowed to reach (used as a redirect
  /// target when a route guard denies access).
  String landingRoute() {
    const order = <(String, String)>[
      ('maquinas.view', '/machines'),
      ('inspecciones.view', '/history'),
      ('incidencias.view', '/incidencias'),
      ('informes.view', '/reports'),
      ('estadisticas.view', '/stats'),
      ('repuestos.view', '/repuestos'),
      ('admin.view', '/admin'),
    ];
    for (final (key, route) in order) {
      if (can(key)) return route;
    }
    return '/no-access';
  }

  void reset() {
    _role = null;
    _loadedForRole = null;
    _perms = {};
  }

  @visibleForTesting
  void debugSet(String? role, Map<String, bool> perms) {
    _role = role;
    _loadedForRole = role;
    _perms = Map.of(perms);
  }
}
