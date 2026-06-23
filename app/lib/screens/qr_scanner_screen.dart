import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;
    setState(() => _processing = true);
    try {
      final machine = await widget.api.getMachineByQr(code);
      if (mounted) context.pushReplacement('/machines/${machine.id}');
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Máquina no encontrada para código: $code')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    if (isDesktop) {
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
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          if (_processing)
            const Center(child: CircularProgressIndicator()),
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
