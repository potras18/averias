import 'package:flutter/material.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/spare_part.dart';
import '../services/api_client.dart';
import 'status_badge.dart';

const _inspectionsPerPage = 10;

class MachineHistoryDetailBody extends StatefulWidget {
  final ApiClient api;
  final String machineId;

  const MachineHistoryDetailBody({
    super.key,
    required this.api,
    required this.machineId,
  });

  @override
  State<MachineHistoryDetailBody> createState() => _MachineHistoryDetailBodyState();
}

class _MachineHistoryDetailBodyState extends State<MachineHistoryDetailBody> {
  late Future<(Machine, List<Inspection>, List<SparePart>)> _future;
  int _inspectionPage = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Machine, List<Inspection>, List<SparePart>)> _load() async {
    final results = await Future.wait([
      widget.api.getMachineById(widget.machineId),
      widget.api.getInspections(machineId: widget.machineId),
      widget.api.getSpareParts(machineId: widget.machineId),
    ]);
    return (
      results[0] as Machine,
      results[1] as List<Inspection>,
      results[2] as List<SparePart>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Machine, List<Inspection>, List<SparePart>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final (machine, inspections, parts) = snap.data!;
        final totalInspectionPages = (inspections.length / _inspectionsPerPage).ceil();
        final inspectionPageStart = _inspectionPage * _inspectionsPerPage;
        final inspectionPageItems = inspections.skip(inspectionPageStart).take(_inspectionsPerPage).toList();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(machine.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(machine.locationName ?? '-', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Estado actual: '),
              StatusBadge(status: machine.lastStatus),
            ]),
            const SizedBox(height: 24),
            Text('Historial de inspecciones (${inspections.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (inspections.isEmpty)
              const Text('Sin inspecciones registradas')
            else
              ...inspectionPageItems.map((i) => _HistoryInspectionTile(key: ValueKey(i.id), inspection: i)),
            if (totalInspectionPages > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Anterior',
                      onPressed: _inspectionPage > 0
                          ? () => setState(() => _inspectionPage--)
                          : null,
                    ),
                    Text('Página ${_inspectionPage + 1} de $totalInspectionPages'),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Siguiente',
                      onPressed: _inspectionPage < totalInspectionPages - 1
                          ? () => setState(() => _inspectionPage++)
                          : null,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 32),
            Text('Historial de repuestos (${parts.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (parts.isEmpty)
              const Text('Sin repuestos registrados')
            else
              ...parts.map((p) => _HistorySparePartTile(part: p)),
          ],
        );
      },
    );
  }
}

class _HistoryInspectionTile extends StatelessWidget {
  final Inspection inspection;
  const _HistoryInspectionTile({super.key, required this.inspection});

  @override
  Widget build(BuildContext context) {
    final d = inspection.inspectedAt;
    final dateStr = '${d.day}/${d.month}/${d.year}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(inspection.technicianName ?? 'Técnico'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateStr, style: Theme.of(context).textTheme.bodySmall),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: StatusBadge(status: inspection.status),
            ),
            if (inspection.comment != null && inspection.comment!.isNotEmpty)
              Text(inspection.comment!),
            if (inspection.cardReaderFailureType != null)
              Text('Lector: ${inspection.cardReaderFailureType}',
                  style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

class _HistorySparePartTile extends StatelessWidget {
  final SparePart part;
  const _HistorySparePartTile({required this.part});

  Color _statusColor() => switch (part.status) {
        'pedido' => Colors.blue,
        'recibido' => Colors.green,
        'instalado' => Colors.teal,
        _ => Colors.orange,
      };

  String _statusLabel() => switch (part.status) {
        'pedido' => 'Pedido',
        'recibido' => 'Recibido',
        'instalado' => 'Instalado',
        _ => 'Pendiente',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(part.description),
        subtitle: Text(
          'Cantidad: ${part.quantity} · ${part.createdByName}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Chip(
          label: Text(_statusLabel(), style: const TextStyle(color: Colors.white, fontSize: 12)),
          backgroundColor: _statusColor(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
