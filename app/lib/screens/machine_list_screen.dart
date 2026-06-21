import 'package:flutter/material.dart';
import '../services/api_client.dart';

class MachineListScreen extends StatelessWidget {
  final ApiClient api;
  const MachineListScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Machines')));
}
