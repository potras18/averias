# Autenticación biométrica (huella dactilar)

**Fecha:** 2026-06-29

## Objetivo

Permitir al usuario acceder a la app con huella dactilar en lugar del formulario de email/contraseña, una vez haya iniciado sesión al menos una vez. El acceso biométrico es opcional y se activa mediante un diálogo tras el primer login exitoso.

## Comportamiento

### Primer login (o biométrico no activado)
1. App abre → formulario de email/contraseña normal.
2. Login exitoso → si el dispositivo soporta biométricos y la opción no está activada → mostrar diálogo: **"¿Activar acceso con huella dactilar?"** con botones "Activar" y "Ahora no".
3. Si el usuario acepta → `biometric_enabled = true` en SecureStorage.

### Siguientes aperturas (biométrico activado)
1. App abre → `initState` de `LoginScreen` detecta: token almacenado + `biometric_enabled == true`.
2. Pide huella automáticamente (sin que el usuario tenga que tocar nada).
3. **Éxito** → `context.go('/machines')`.
4. **Fallo o cancelación** → muestra formulario email/contraseña como fallback (sin mensaje de error, estado limpio).

### Logout
- La preferencia `biometric_enabled` se conserva tras logout. En el siguiente login con email/contraseña se ofrecerá activarlo de nuevo si estaba desactivado o si es un dispositivo nuevo.

## Seguridad

- La huella **no sustituye al token JWT** — solo desbloquea el acceso a los tokens ya almacenados en `flutter_secure_storage`.
- Si el token expira mientras la app está cerrada, el refresh se intenta automáticamente (flujo ya existente en `ApiClient`). Si falla → formulario de login normal.
- Solo disponible en móvil (Android). La pantalla de escritorio no muestra la opción.

## Arquitectura

### `StorageService` (modificar)
Añadir dos métodos:
```dart
Future<bool> getBiometricEnabled() async {
  return (await _storage.read(key: _keyBiometricEnabled)) == 'true';
}
Future<void> setBiometricEnabled(bool value) =>
    _storage.write(key: _keyBiometricEnabled, value: value.toString());
```
Clave: `static const _keyBiometricEnabled = 'biometric_enabled';`

El método `clear()` existente **no borra** `_keyBiometricEnabled` — la preferencia persiste entre sesiones.

### `BiometricService` (nuevo — `app/lib/services/biometric_service.dart`)
Wrapper sobre `local_auth`:
```dart
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    if (!await _auth.canCheckBiometrics) return false;
    final biometrics = await _auth.getAvailableBiometrics();
    return biometrics.isNotEmpty;
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Accede a Averías',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }
}
```

### `LoginScreen` (modificar)

**`initState`:** crear `BiometricService` e intentar auto-autenticación:
```dart
@override
void initState() {
  super.initState();
  _auth = AuthService(api: widget.api, storage: widget.storage);
  _biometric = BiometricService();
  WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
}

Future<void> _tryBiometric() async {
  final token = await widget.storage.getAccessToken();
  final enabled = await widget.storage.getBiometricEnabled();
  if (!mounted || token == null || !enabled) return;
  final ok = await _biometric.authenticate();
  if (mounted && ok) context.go('/machines');
  // si falla: no hacer nada, el formulario ya está visible
}
```

**Tras login exitoso con email/contraseña:**
```dart
Future<void> _submit() async {
  // ... login existente ...
  await _auth.login(...);
  await _offerBiometric();
  if (mounted) context.go('/machines');
}

Future<void> _offerBiometric() async {
  final alreadyEnabled = await widget.storage.getBiometricEnabled();
  if (alreadyEnabled) return;
  final available = await _biometric.isAvailable();
  if (!available || !mounted) return;
  final accept = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Acceso con huella'),
      content: const Text('¿Activar el acceso con huella dactilar la próxima vez?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Activar')),
      ],
    ),
  );
  if (accept == true) await widget.storage.setBiometricEnabled(true);
}
```

## Plataforma

### Android
- Permiso en `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
  ```
- `minSdkVersion` debe ser ≥ 23 (ya cumplido en este proyecto).

### `pubspec.yaml`
```yaml
dependencies:
  local_auth: ^2.3.0
```

## Archivos a modificar/crear

| Archivo | Cambio |
|---------|--------|
| `app/pubspec.yaml` | añadir `local_auth: ^2.3.0` |
| `android/app/src/main/AndroidManifest.xml` | añadir permiso `USE_BIOMETRIC` |
| `app/lib/services/storage_service.dart` | añadir `_keyBiometricEnabled`, `getBiometricEnabled()`, `setBiometricEnabled()` |
| `app/lib/services/biometric_service.dart` | nuevo — `BiometricService` |
| `app/lib/screens/login_screen.dart` | auto-prompt en `initState`, diálogo de activación tras login |

## No incluido en este scope

- Desactivar biométrico desde ajustes (el usuario puede desactivarlo reiniciando sesión y eligiendo "Ahora no").
- Soporte iOS (Face ID / Touch ID) — no hay dispositivos iOS en este proyecto.
- Bloqueo de app al volver del fondo.
