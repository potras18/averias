import 'package:flutter/material.dart';
import '../services/api_client.dart';

class QrScannerScreen extends StatelessWidget {
  final ApiClient api;
  const QrScannerScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Scan')));
}
