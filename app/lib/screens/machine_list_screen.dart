import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../services/api_client.dart';
import '../widgets/machine_card.dart';

class MachineListScreen extends StatefulWidget {
  final ApiClient api;
  const MachineListScreen({super.key, required this.api});

  @override
  State<MachineListScreen> createState() => _MachineListScreenState();
}

class _MachineListScreenState extends State<MachineListScreen> {
  late Future<List<Machine>> _machinesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() { _machinesFuture = widget.api.getMachines(); });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Máquinas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Estadísticas',
            onPressed: () => context.push('/stats'),
          ),
          IconButton(
            icon: const Icon(Icons.assessment),
            tooltip: 'Informes',
            onPressed: () => context.push('/reports'),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear QR',
            onPressed: () => context.push('/scan'),
          ),
        ],
      ),
      body: FutureBuilder<List<Machine>>(
        future: _machinesFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Error al cargar máquinas'),
                  TextButton(onPressed: _reload, child: const Text('Reintentar')),
                ],
              ),
            );
          }
          final machines = snap.data!;
          if (machines.isEmpty) {
            return const Center(child: Text('Sin máquinas registradas'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              itemCount: machines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => MachineCard(
                machine: machines[i],
                onTap: () => context.push('/machines/${machines[i].id}'),
              ),
            ),
          );
        },
      ),
    );
  }
}
