// averias/app/lib/screens/machine_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/spare_part.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/status_badge.dart';
import '../widgets/desktop_shell_scope.dart';
import '../widgets/section_card.dart';
import '../widgets/machine_photo.dart';
import '../widgets/confirm_dialog.dart';

class MachineDetailScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final String machineId;
  const MachineDetailScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.machineId,
  });

  @override
  State<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

class _MachineDetailScreenState extends State<MachineDetailScreen>
    with SingleTickerProviderStateMixin {
  late Future<Machine> _machineFuture;
  late Future<List<SparePart>> _partsFuture;
  late TabController _tabController;
  bool _redirected = false;
  String? _role;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _machineFuture = widget.api.getMachineById(widget.machineId);
    _partsFuture   = widget.api.getSpareParts(machineId: widget.machineId);
    widget.storage.getRole().then((r)   { if (mounted) setState(() => _role = r); });
    widget.storage.getUserId().then((id) { if (mounted) setState(() => _userId = id); });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reloadParts() => setState(() {
        _partsFuture = widget.api.getSpareParts(machineId: widget.machineId);
      });

  void _openEdit(Machine machine, Inspection inspection) {
    context.push(
      '/machines/${machine.id}/inspect',
      extra: {
        'hasRedemptionTickets': machine.hasRedemptionTickets,
        'inspection': inspection,
      },
    ).then((_) => setState(() {
          _machineFuture = widget.api.getMachineById(widget.machineId);
        }));
  }

  Future<void> _deleteInspection(Inspection inspection) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Borrar inspección',
      message: '¿Borrar esta inspección? No se puede deshacer.',
      confirmLabel: 'Borrar',
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteInspection(inspection.id);
      if (mounted) setState(() {
        _machineFuture = widget.api.getMachineById(widget.machineId);
      });
    } on DioException catch (e) {
      final message = e.response?.statusCode == 409
          ? (e.response?.data?['error'] as String? ?? 'No se pudo borrar la inspección')
          : 'No se pudo borrar la inspección';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    return FutureBuilder<Machine>(
      future: _machineFuture,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: isDesktop ? null : AppBar(),
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }
        final machine = snap.data!;
        if (isDesktop) {
          if (!_redirected) {
            _redirected = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/machines?selected=${machine.id}');
            });
          }
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(machine.name),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Inspecciones'),
                Tab(text: 'Repuestos'),
              ],
            ),
          ),
          floatingActionButton: ListenableBuilder(
            listenable: _tabController,
            builder: (_, __) {
              if (_tabController.index != 1) return const SizedBox.shrink();
              return FloatingActionButton(
                onPressed: () => context
                    .push('/repuestos/new', extra: {'machineId': machine.id})
                    .then((_) => _reloadParts()),
                child: const Icon(Icons.add),
              );
            },
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // Tab 0: Inspecciones
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  MachinePhoto(
                    api: widget.api,
                    machineId: machine.id,
                    hasImage: machine.hasImage,
                    role: _role,
                    onChanged: () => setState(() {
                      _machineFuture = widget.api.getMachineById(widget.machineId);
                    }),
                  ),
                  _InfoRow('Local', machine.locationName ?? '-'),
                  _InfoRow('Tickets redemption', machine.hasRedemptionTickets ? 'Sí' : 'No'),
                  const SizedBox(height: 16),
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
                            extra: {
                              'hasRedemptionTickets': machine.hasRedemptionTickets,
                              'inspection': null,
                            })
                        .then((_) => setState(() {
                              _machineFuture =
                                  widget.api.getMachineById(widget.machineId);
                            })),
                  ),
                  const SizedBox(height: 24),
                  SectionCard(
                    icon: Icons.checklist,
                    title: 'Últimas inspecciones',
                    children: [
                      if (machine.inspections.isEmpty)
                        const Text('Sin inspecciones previas')
                      else
                        ...machine.inspections.map((i) => _InspectionTile(
                              inspection: i,
                              role: _role,
                              currentUserId: _userId,
                              onEdit: () => _openEdit(machine, i),
                              onDelete: () => _deleteInspection(i),
                            )),
                    ],
                  ),
                ],
              ),
              // Tab 1: Repuestos
              FutureBuilder<List<SparePart>>(
                future: _partsFuture,
                builder: (context, partsSnap) {
                  if (!partsSnap.hasData &&
                      partsSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (partsSnap.hasError) {
                    return Center(child: Text('Error: ${partsSnap.error}'));
                  }
                  final parts = partsSnap.data!;
                  if (parts.isEmpty) {
                    return const Center(
                        child: Text('Sin repuestos para esta máquina'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: parts.length,
                    itemBuilder: (_, i) => _SparePartTile(
                      part: parts[i],
                      onEdit: () => context
                          .push('/repuestos/${parts[i].id}/edit',
                              extra: {'sparePart': parts[i]})
                          .then((_) => _reloadParts()),
                    ),
                  );
                },
              ),
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
  final String? role;
  final String? currentUserId;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _InspectionTile({
    required this.inspection,
    this.role,
    this.currentUserId,
    this.onEdit,
    this.onDelete,
  });

  bool _canEdit() {
    if (role == null) return false;
    if (role == 'admin') return true;
    final today = DateTime.now();
    final d = inspection.inspectedAt;
    final isToday =
        d.year == today.year && d.month == today.month && d.day == today.day;
    return isToday && inspection.technicianId == currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${inspection.inspectedAt.day}/${inspection.inspectedAt.month}/${inspection.inspectedAt.year}';
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canEdit())
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Editar inspección',
                onPressed: onEdit,
              ),
            if (role == 'admin')
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Borrar inspección',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _SparePartTile extends StatelessWidget {
  final SparePart part;
  final VoidCallback onEdit;

  const _SparePartTile({required this.part, required this.onEdit});

  Color _statusColor() => switch (part.status) {
        'pedido'    => Colors.blue,
        'recibido'  => Colors.green,
        'instalado' => Colors.teal,
        _           => Colors.orange,
      };

  String _statusLabel() => switch (part.status) {
        'pedido'    => 'Pedido',
        'recibido'  => 'Recibido',
        'instalado' => 'Instalado',
        _           => 'Pendiente',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(part.description),
        subtitle: Text(
          'Cantidad: ${part.quantity}  ·  ${part.createdByName}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(_statusLabel(),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              backgroundColor: _statusColor(),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar',
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}
