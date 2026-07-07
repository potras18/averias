// app/lib/screens/login_screen.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/storage_service.dart';
import '../widgets/confirm_dialog.dart';

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
  bool _obscure = true;
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
      if (mounted) setState(() { _loading = false; });
      await _offerBiometric();
      if (mounted) context.go('/machines');
    } catch (e) {
      setState(() { _error = _loginErrorMessage(e); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  String _loginErrorMessage(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.badResponse) {
        final code = e.response?.statusCode;
        switch (code) {
          case 401:
            return 'Credenciales incorrectas';
          case 429:
            return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
          default:
            return 'Error del servidor (código $code). Inténtalo más tarde.';
        }
      }
      return 'No se puede conectar al servidor. Revisa tu conexión (${e.message}).';
    }
    return 'Error inesperado al iniciar sesión: $e';
  }

  Future<void> _offerBiometric() async {
    final alreadyEnabled = await widget.storage.getBiometricEnabled();
    if (alreadyEnabled) return;
    final available = await _biometric.isAvailable();
    if (!available || !mounted) return;
    final accept = await showConfirmDialog(
      context,
      title: 'Acceso con huella',
      message: '¿Activar el acceso con huella dactilar la próxima vez?',
      confirmLabel: 'Activar',
      cancelLabel: 'Ahora no',
    );
    if (accept) await widget.storage.setBiometricEnabled(true);
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
                  Image.asset(
                    'assets/images/cocamatic-logo.png',
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sistema de revisiones',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || !v.contains('@')) ? 'Email inválido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passCtrl,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _loading ? null : _submit(),
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
