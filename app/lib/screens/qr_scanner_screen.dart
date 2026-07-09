import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../widgets/desktop_shell_scope.dart';

class QrScannerScreen extends StatefulWidget {
  final ApiClient api;
  const QrScannerScreen({super.key, required this.api});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _processing = false;
  String? _cameraError;

  void _onControllerCreated(CameraController? controller, Exception? error) {
    if (error != null && mounted) {
      setState(() => _cameraError = error.toString());
    }
  }

  Future<void> _onScan(Code? code) async {
    if (_processing) return;
    final value = code?.text;
    if (code?.isValid != true || value == null) return;
    setState(() => _processing = true);
    try {
      final machine = await widget.api.getMachineByQr(value);
      if (mounted) context.pushReplacement('/machines/${machine.id}');
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Máquina no encontrada para código: $value')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    // flutter_zxing uses dart:ffi, which isn't available on web — fall back to
    // the same "use the mobile app" message there, regardless of screen size.
    if (isDesktop || kIsWeb) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Usa la app móvil para escanear QR',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: _cameraError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'No se pudo iniciar la cámara.\n$_cameraError',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _cameraError = null),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                ReaderWidget(
                  codeFormat: Format.qrCode,
                  showGallery: false,
                  onScan: _onScan,
                  onControllerCreated: _onControllerCreated,
                ),
                if (_processing) const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
