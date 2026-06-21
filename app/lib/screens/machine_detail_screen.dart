import 'package:flutter/material.dart';
import '../services/api_client.dart';

class MachineDetailScreen extends StatelessWidget {
  final ApiClient api;
  final String machineId;
  const MachineDetailScreen({super.key, required this.api, required this.machineId});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Detail')));
}
