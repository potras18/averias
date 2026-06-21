// averias/app/lib/screens/machine_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../services/api_client.dart';
import '../widgets/status_badge.dart';

class MachineDetailScreen extends StatefulWidget {
  final ApiClient api;
  final String machineId;
  const MachineDetailScreen({super.key, required this.api, required this.machineId});

  @override
  State<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

class _MachineDetailScreenState extends State<MachineDetailScreen> {
  late Future<Machine> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMachineById(widget.machineId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Machine>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }
        final machine = snap.data!;
        return Scaffold(
          appBar: AppBar(title: Text(machine.name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoRow('Local', machine.locationName ?? '-'),
              _InfoRow('Código QR', machine.qrCode),
              _InfoRow('Tickets redemption', machine.hasRedemptionTickets ? 'Sí' : 'No'),
              const SizedBox(height: 16),
              Center(
                child: QrImageView(
                  data: machine.qrCode,
                  version: QrVersions.auto,
                  size: 160,
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text(machine.qrCode, style: Theme.of(context).textTheme.bodySmall)),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Estado actual: '),
                StatusBadge(status: machine.lastStatus),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar inspección'),
                onPressed: () => context
                    .push('/machines/${machine.id}/inspect',
                        extra: machine.hasRedemptionTickets)
                    .then((_) => setState(() {
                          _future = widget.api.getMachineById(widget.machineId);
                        })),
              ),
              const SizedBox(height: 24),
              Text('Últimas inspecciones', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (machine.inspections.isEmpty)
                const Text('Sin inspecciones previas')
              else
                ...machine.inspections.map((i) => _InspectionTile(inspection: i)),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(value)),
      ]),
    );
  }
}

class _InspectionTile extends StatelessWidget {
  final Inspection inspection;
  const _InspectionTile({required this.inspection});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(inspection.technicianName ?? 'Técnico'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(inspection.comment ?? ''),
            if (inspection.cardReaderFailureType != null)
              Text('Lector: ${inspection.cardReaderFailureType}',
                  style: const TextStyle(color: Colors.red)),
          ],
        ),
        trailing: Text(
          '${inspection.inspectedAt.day}/${inspection.inspectedAt.month}/${inspection.inspectedAt.year}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
