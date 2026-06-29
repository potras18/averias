# Biometric Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to log in with fingerprint biometrics on Android mobile, with automatic prompt on startup if previously enabled and fallback to email/password.

**Architecture:** Three sequential tasks — (1) add dependency + platform permission + StorageService methods; (2) new BiometricService wrapper over local_auth with injectable LocalAuthentication for testability; (3) modify LoginScreen to auto-prompt biometrics in initState and offer enrollment dialog after email/password login.

**Tech Stack:** Flutter, `local_auth: ^2.3.0`, `flutter_secure_storage` (already installed), `mocktail` (already installed for tests), Android (only — no iOS scope).

## Global Constraints

- `local_auth` version exactly `^2.3.0`
- Android permission `android.permission.USE_BIOMETRIC` added in `AndroidManifest.xml`
- `biometric_enabled` key in `flutter_secure_storage` is NOT cleared on logout (intentional — `clear()` in `StorageService` must not touch it)
- Biometric feature only shown/active on mobile (`kIsWeb` or `DesktopShellScope` is not relevant — the feature is platform-transparent but will silently be unavailable on desktop because `canCheckBiometrics` returns false)
- Spanish UI strings: `'Acceso con huella'`, `'¿Activar el acceso con huella dactilar la próxima vez?'`, `'Ahora no'`, `'Activar'`, `'Accede a Averías'`
- No biometric "disable" setting in this scope — user loses biometric by logging out and choosing "Ahora no"
- TDD: failing test first, verify fail, implement, verify pass, commit
- Test command: `flutter test` from the `app/` directory

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `app/pubspec.yaml` | Modify | Add `local_auth: ^2.3.0` |
| `app/android/app/src/main/AndroidManifest.xml` | Modify | Add `USE_BIOMETRIC` permission |
| `app/lib/services/storage_service.dart` | Modify | Add `_keyBiometricEnabled`, `getBiometricEnabled()`, `setBiometricEnabled()` |
| `app/lib/services/biometric_service.dart` | Create | Wrapper over `local_auth` — `isAvailable()`, `authenticate()` |
| `app/test/services/biometric_service_test.dart` | Create | Unit tests for BiometricService |
| `app/lib/screens/login_screen.dart` | Modify | Auto-prompt in `initState`, enrollment dialog after email/password login |
| `app/test/screens/login_screen_test.dart` | Create | Widget tests for both biometric flows |

---

### Task 1: Dependencies + Platform Permission + StorageService

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/lib/services/storage_service.dart`

**Interfaces:**
- Produces:
  - `StorageService.getBiometricEnabled() → Future<bool>`
  - `StorageService.setBiometricEnabled(bool value) → Future<void>`
  - `StorageService.clear()` does NOT clear `biometric_enabled` key

- [ ] **Step 1: Write the failing compile test**

`StorageService` has no biometric methods yet. Write a test in `app/test/services/auth_service_test.dart` that stubs the new methods on `MockStorageService`. Since `MockStorageService` is `Mock implements StorageService`, adding the method to `StorageService` will make the mock work; calling it before the method exists will produce a compile error.

Add at the end of the `main()` function in `app/test/services/auth_service_test.dart`:

```dart
  test('storage: getBiometricEnabled returns mocked value', () async {
    when(() => mockStorage.getBiometricEnabled()).thenAnswer((_) async => true);
    expect(await mockStorage.getBiometricEnabled(), isTrue);
  });

  test('storage: setBiometricEnabled calls mock without error', () async {
    when(() => mockStorage.setBiometricEnabled(true)).thenAnswer((_) async {});
    await mockStorage.setBiometricEnabled(true);
    verify(() => mockStorage.setBiometricEnabled(true)).called(1);
  });
```

- [ ] **Step 2: Run test to verify compile error (expected fail)**

```bash
cd app && flutter test test/services/auth_service_test.dart
```

Expected output: error mentioning `getBiometricEnabled` is not defined on `StorageService` (or similar compile error). If tests pass with no errors, the method already exists — skip to Step 5.

- [ ] **Step 3: Add `local_auth` to `app/pubspec.yaml`**

In the `dependencies:` block, after `mobile_scanner: ^5.2.1`, add:

```yaml
  local_auth: ^2.3.0
```

Run:

```bash
cd app && flutter pub get
```

Expected: resolves without error, `pubspec.lock` updated.

- [ ] **Step 4: Add `USE_BIOMETRIC` permission to `app/android/app/src/main/AndroidManifest.xml`**

Add after the existing `<uses-permission android:name="android.permission.CAMERA"/>` line:

```xml
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
```

- [ ] **Step 5: Add biometric methods to `StorageService`**

In `app/lib/services/storage_service.dart`, add the key constant and two methods. The final file:

```dart
// app/lib/services/storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage  = FlutterSecureStorage();
  static const _keyAccess   = 'access_token';
  static const _keyRefresh  = 'refresh_token';
  static const _keyRole     = 'user_role';
  static const _keyUserId   = 'user_id';
  static const _keyBiometricEnabled = 'biometric_enabled';

  Future<String?> getAccessToken()  => _storage.read(key: _keyAccess);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefresh);
  Future<String?> getRole()         => _storage.read(key: _keyRole);
  Future<String?> getUserId()       => _storage.read(key: _keyUserId);

  Future<bool> getBiometricEnabled() async =>
      (await _storage.read(key: _keyBiometricEnabled)) == 'true';

  Future<void> setBiometricEnabled(bool value) =>
      _storage.write(key: _keyBiometricEnabled, value: value.toString());

  Future<void> setTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _keyAccess,   value: accessToken);
    await _storage.write(key: _keyRefresh,  value: refreshToken);
  }

  Future<void> setUserMeta({required String role, required String userId}) async {
    await _storage.write(key: _keyRole,   value: role);
    await _storage.write(key: _keyUserId, value: userId);
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
    await _storage.delete(key: _keyRole);
    await _storage.delete(key: _keyUserId);
    // _keyBiometricEnabled intentionally NOT cleared — persists across sessions
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd app && flutter test test/services/auth_service_test.dart
```

Expected: all tests pass including the two new ones.

- [ ] **Step 7: Verify full test suite still passes**

```bash
cd app && flutter test
```

Expected: all tests pass, no regressions.

- [ ] **Step 8: Commit**

```bash
cd app && git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml lib/services/storage_service.dart test/services/auth_service_test.dart
git commit -m "feat: add local_auth dependency and biometric storage methods"
```

---

### Task 2: BiometricService

**Files:**
- Create: `app/lib/services/biometric_service.dart`
- Create: `app/test/services/biometric_service_test.dart`

**Interfaces:**
- Consumes: `local_auth` package (`LocalAuthentication`, `AuthenticationOptions`)
- Produces:
  - `BiometricService({LocalAuthentication? auth})` — constructor, optional injectable auth
  - `BiometricService.isAvailable() → Future<bool>` — true only if `canCheckBiometrics` is true AND `getAvailableBiometrics()` returns non-empty list
  - `BiometricService.authenticate() → Future<bool>` — calls `_auth.authenticate(...)`, catches any exception and returns false

- [ ] **Step 1: Write failing tests**

Create `app/test/services/biometric_service_test.dart`:

```dart
// app/test/services/biometric_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/services/biometric_service.dart';

class MockLocalAuthentication extends Mock implements LocalAuthentication {}

void main() {
  late MockLocalAuthentication mockAuth;
  late BiometricService service;

  setUp(() {
    mockAuth = MockLocalAuthentication();
    service = BiometricService(auth: mockAuth);
  });

  group('isAvailable', () {
    test('returns false when canCheckBiometrics is false', () async {
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => false);
      expect(await service.isAvailable(), isFalse);
    });

    test('returns false when biometrics list is empty', () async {
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => true);
      when(() => mockAuth.getAvailableBiometrics()).thenAnswer((_) async => []);
      expect(await service.isAvailable(), isFalse);
    });

    test('returns true when biometrics are available', () async {
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => true);
      when(() => mockAuth.getAvailableBiometrics())
          .thenAnswer((_) async => [BiometricType.fingerprint]);
      expect(await service.isAvailable(), isTrue);
    });
  });

  group('authenticate', () {
    test('returns true on success', () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => true);
      expect(await service.authenticate(), isTrue);
    });

    test('returns false when authentication fails', () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => false);
      expect(await service.authenticate(), isFalse);
    });

    test('returns false when exception thrown', () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenThrow(Exception('platform error'));
      expect(await service.authenticate(), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/services/biometric_service_test.dart
```

Expected: error that `biometric_service.dart` does not exist (import fails).

- [ ] **Step 3: Create `app/lib/services/biometric_service.dart`**

```dart
// app/lib/services/biometric_service.dart
import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

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

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/services/biometric_service_test.dart
```

Expected: all 6 tests pass.

- [ ] **Step 5: Run full test suite**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd app && git add lib/services/biometric_service.dart test/services/biometric_service_test.dart
git commit -m "feat: add BiometricService wrapper for local_auth"
```

---

### Task 3: LoginScreen Biometric Integration

**Files:**
- Modify: `app/lib/screens/login_screen.dart`
- Create: `app/test/screens/login_screen_test.dart`

**Interfaces:**
- Consumes (from Task 1): `StorageService.getBiometricEnabled()`, `StorageService.setBiometricEnabled()`
- Consumes (from Task 2): `BiometricService.isAvailable()`, `BiometricService.authenticate()`
- Produces: `LoginScreen({..., BiometricService? biometric})` — optional injectable biometric service; defaults to `BiometricService()`

**Behavior summary:**
- `initState` → `WidgetsBinding.addPostFrameCallback` → `_tryBiometric()`:
  - Read `storage.getAccessToken()` and `storage.getBiometricEnabled()`
  - If token is non-null AND `biometricEnabled == true` → call `biometric.authenticate()`
  - If authenticate returns true → `context.go('/machines')`
  - If authenticate returns false or either flag missing → do nothing (form visible)
- `_submit()` (email/password login):
  - After `_auth.login(...)` succeeds → call `_offerBiometric()`
  - Then `context.go('/machines')`
- `_offerBiometric()`:
  - `getBiometricEnabled()` → if already true → return early
  - `biometric.isAvailable()` → if false → return early
  - Show `AlertDialog` with title `'Acceso con huella'`, content `'¿Activar el acceso con huella dactilar la próxima vez?'`
  - Button `'Ahora no'` → `Navigator.pop(context, false)`
  - Button `'Activar'` → `Navigator.pop(context, true)`
  - If result == true → `storage.setBiometricEnabled(true)`

- [ ] **Step 1: Write failing tests**

Create `app/test/screens/login_screen_test.dart`:

```dart
// app/test/screens/login_screen_test.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/login_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/services/biometric_service.dart';
import 'package:averias_app/services/storage_service.dart';

class MockApiClient extends Mock implements ApiClient {}
class MockStorageService extends Mock implements StorageService {}
class MockBiometricService extends Mock implements BiometricService {}

GoRouter _router(LoginScreen screen) => GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => screen),
        GoRoute(path: '/machines', builder: (_, __) => const Scaffold(body: Text('machines'))),
      ],
    );

Widget _wrap(LoginScreen screen) => MaterialApp.router(routerConfig: _router(screen));

void main() {
  late MockApiClient api;
  late MockStorageService storage;
  late MockBiometricService biometric;

  setUp(() {
    api = MockApiClient();
    storage = MockStorageService();
    biometric = MockBiometricService();

    // default: no token, biometric disabled
    when(() => storage.getAccessToken()).thenAnswer((_) async => null);
    when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
    when(() => storage.setBiometricEnabled(any())).thenAnswer((_) async {});
    when(() => biometric.isAvailable()).thenAnswer((_) async => false);
    when(() => biometric.authenticate()).thenAnswer((_) async => false);
  });

  LoginScreen _build() => LoginScreen(api: api, storage: storage, biometric: biometric);

  group('biometric auto-prompt on startup', () {
    testWidgets('does not authenticate when no token stored', (tester) async {
      when(() => storage.getAccessToken()).thenAnswer((_) async => null);
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      verifyNever(() => biometric.authenticate());
    });

    testWidgets('does not authenticate when biometric_enabled is false', (tester) async {
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      verifyNever(() => biometric.authenticate());
    });

    testWidgets('navigates to /machines when biometric succeeds', (tester) async {
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => true);
      when(() => biometric.authenticate()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      verify(() => biometric.authenticate()).called(1);
      expect(find.text('machines'), findsOneWidget);
    });

    testWidgets('shows form when biometric fails', (tester) async {
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => true);
      when(() => biometric.authenticate()).thenAnswer((_) async => false);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('machines'), findsNothing);
    });
  });

  group('biometric enrollment after email/password login', () {
    setUp(() {
      when(() => api.login(any(), any())).thenAnswer((_) async => {
        'accessToken': 'tok',
        'refreshToken': 'ref',
        'user': {'id': 'u1', 'name': 'Tech', 'email': 'a@a.com', 'role': 'technician'},
      });
      when(() => storage.setTokens(accessToken: any(named: 'accessToken'), refreshToken: any(named: 'refreshToken')))
          .thenAnswer((_) async {});
      when(() => storage.setUserMeta(role: any(named: 'role'), userId: any(named: 'userId')))
          .thenAnswer((_) async {});
    });

    testWidgets('shows enrollment dialog when biometrics available and not enabled', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
      when(() => biometric.isAvailable()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Acceso con huella'), findsOneWidget);
      expect(find.text('¿Activar el acceso con huella dactilar la próxima vez?'), findsOneWidget);
    });

    testWidgets('calls setBiometricEnabled(true) when user taps Activar', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
      when(() => biometric.isAvailable()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Activar'));
      await tester.pumpAndSettle();

      verify(() => storage.setBiometricEnabled(true)).called(1);
    });

    testWidgets('does not call setBiometricEnabled when user taps Ahora no', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
      when(() => biometric.isAvailable()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      verifyNever(() => storage.setBiometricEnabled(any()));
    });

    testWidgets('skips dialog when biometrics not available', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => false);
      when(() => biometric.isAvailable()).thenAnswer((_) async => false);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Acceso con huella'), findsNothing);
      expect(find.text('machines'), findsOneWidget);
    });

    testWidgets('skips dialog when biometric already enabled', (tester) async {
      when(() => storage.getBiometricEnabled()).thenAnswer((_) async => true);
      when(() => storage.getAccessToken()).thenAnswer((_) async => null);
      when(() => biometric.isAvailable()).thenAnswer((_) async => true);

      await tester.pumpWidget(_wrap(_build()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'a@a.com');
      await tester.enterText(find.byType(TextFormField).last, 'pass');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Acceso con huella'), findsNothing);
      expect(find.text('machines'), findsOneWidget);
      verifyNever(() => storage.setBiometricEnabled(any()));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/screens/login_screen_test.dart
```

Expected: compile error — `LoginScreen` constructor has no `biometric` parameter yet.

- [ ] **Step 3: Implement biometric integration in LoginScreen**

Replace `app/lib/screens/login_screen.dart` with:

```dart
// app/lib/screens/login_screen.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/storage_service.dart';

class LoginScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final BiometricService? biometric;

  const LoginScreen({
    super.key,
    required this.api,
    required this.storage,
    this.biometric,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  late final AuthService _auth;
  late final BiometricService _biometric;

  @override
  void initState() {
    super.initState();
    _auth = AuthService(api: widget.api, storage: widget.storage);
    _biometric = widget.biometric ?? BiometricService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final token = await widget.storage.getAccessToken();
    final enabled = await widget.storage.getBiometricEnabled();
    if (!mounted || token == null || !enabled) return;
    final ok = await _biometric.authenticate();
    if (mounted && ok) context.go('/machines');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.login(_emailCtrl.text.trim(), _passCtrl.text);
      await _offerBiometric();
      if (mounted) context.go('/machines');
    } catch (e) {
      final msg = (e is DioException && e.type != DioExceptionType.badResponse)
          ? 'No se puede conectar al servidor (${e.message})'
          : 'Credenciales incorrectas';
      setState(() { _error = msg; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (accept == true) await widget.storage.setBiometricEnabled(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Averías', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@')) ? 'Email inválido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passCtrl,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    obscureText: true,
                    validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Entrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/screens/login_screen_test.dart
```

Expected: all 9 tests pass.

- [ ] **Step 5: Run full test suite**

```bash
cd app && flutter test
```

Expected: all tests pass, no regressions.

- [ ] **Step 6: Commit**

```bash
cd app && git add lib/screens/login_screen.dart test/screens/login_screen_test.dart
git commit -m "feat: add biometric authentication to LoginScreen"
```

---

## Self-Review

**Spec coverage:**
- ✅ `local_auth: ^2.3.0` — Task 1
- ✅ `USE_BIOMETRIC` permission — Task 1
- ✅ `getBiometricEnabled()` / `setBiometricEnabled()` on StorageService — Task 1
- ✅ `clear()` does NOT clear `biometric_enabled` — Task 1 (explicit comment in code)
- ✅ `BiometricService` with `isAvailable()` and `authenticate()` — Task 2
- ✅ Auto-prompt biometric in `initState` via `addPostFrameCallback` — Task 3
- ✅ `context.go('/machines')` on biometric success — Task 3
- ✅ Silent fallback to form on biometric failure — Task 3
- ✅ Enrollment dialog after email/password login — Task 3
- ✅ Spanish UI strings (exact) — Task 3
- ✅ Dialog skipped if already enabled — Task 3
- ✅ Dialog skipped if biometrics not available — Task 3
- ✅ `setBiometricEnabled(true)` called only on "Activar" — Task 3

**Placeholder scan:** None found.

**Type consistency:**
- `BiometricService.isAvailable()` produced in Task 2, consumed in Task 3 ✅
- `BiometricService.authenticate()` produced in Task 2, consumed in Task 3 ✅
- `StorageService.getBiometricEnabled()` produced in Task 1, consumed in Tasks 3 ✅
- `StorageService.setBiometricEnabled(bool)` produced in Task 1, consumed in Task 3 ✅
- `LoginScreen({..., BiometricService? biometric})` produced in Task 3, tests use `biometric:` named param ✅
