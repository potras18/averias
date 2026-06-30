import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../models/inspection.dart';
import '../models/spare_part.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/desktop_shell_scope.dart';
import '../widgets/machine_card.dart';
import '../widgets/status_badge.dart';

// Inspection form options (same as InspectionFormScreen)
const _statusOptions = [
  ('operative', 'Operativa'),
  ('out_of_service', 'Fuera de servicio'),
  ('in_repair', 'En reparación'),
];
const _failureTypes = [
  ('no_lee', 'No lee'),
  ('error_comunicacion', 'Error comunicación'),
  ('dano_fisico', 'Daño físico'),
  ('otro', 'Otro'),
];
const _ticketLevels = [
  ('full', 'Lleno'),
  ('low', 'Bajo'),
  ('empty', 'Vacío'),
];

class MachineListScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final String? preselectedId;

  const MachineListScreen({
    super.key,
    required this.api,
    required this.storage,
    this.preselectedId,
  });

  @override
  State<MachineListScreen> createState() => _MachineListScreenState();
}

class _MachineListScreenState extends State<MachineListScreen> {
  List<Machine> _machines = [];
  bool _loadingList = true;
  String? _error;
  String? _role;
  // Desktop state
  String? _selectedMachineId;
  Future<Machine>? _detailFuture;
  Future<List<SparePart>>? _partsFuture;
  String? _userId;
  bool _showForm = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isDesktop = false;
  DateTime _inspectionDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadList();
    _loadRole();
    widget.storage.getUserId().then((id) { if (mounted) setState(() => _userId = id); });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    try {
      final machines = await widget.api.getMachines(
        inspectionDate: _inspectionDate,
      );
      if (!mounted) return;
      setState(() {
        _machines = machines;
        _loadingList = false;
        _error = null;
      });
      if (_isDesktop && machines.isNotEmpty && _selectedMachineId == null) {
        final initialId = widget.preselectedId ?? machines.first.id;
        _selectMachine(initialId);
      }
    } catch (_) {
      if (mounted) setState(() {
        _loadingList = false;
        _error = 'Error al cargar máquinas';
      });
    }
  }

  Future<void> _loadRole() async {
    final role = await widget.storage.getRole();
    if (mounted) setState(() => _role = role);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _inspectionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null && mounted) {
      setState(() {
        _inspectionDate = picked;
        _loadingList = true;
        _searchCtrl.clear();
        _searchQuery = '';
      });
      await _loadList();
    }
  }

  Widget _buildDatePickerRow() {
    final d = _inspectionDate;
    final label =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _pickDate,
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  void _selectMachine(String id) {
    setState(() {
      _selectedMachineId = id;
      _showForm = false;
      _detailFuture = widget.api.getMachineById(id);
      _partsFuture = widget.api.getSpareParts(machineId: id);
    });
  }

  List<Machine> get _filtered {
    if (_searchQuery.isEmpty) return _machines;
    return _machines
        .where((m) => m.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  // ── MOBILE BUILD ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isDesktop) return _buildDesktop(context);
    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Máquinas'),
        actions: [
          if (_role == 'admin')
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Administración',
              onPressed: () => context.push('/admin'),
            ),
          IconButton(
            icon: const Icon(Icons.build),
            tooltip: 'Repuestos',
            onPressed: () => context.push('/repuestos'),
          ),
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
      body: Column(
        children: [
          _buildDatePickerRow(),
          Expanded(
            child: _loadingList
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            TextButton(onPressed: _loadList, child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _machines.isEmpty
                        ? const Center(child: Text('Sin máquinas registradas'))
                        : RefreshIndicator(
                            onRefresh: _loadList,
                            child: ListView.separated(
                              itemCount: _machines.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) => MachineCard(
                                machine: _machines[i],
                                onTap: () => context.push('/machines/${_machines[i].id}'),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  // ── DESKTOP BUILD ─────────────────────────────────────────────────────────
  Widget _buildDesktop(BuildContext context) {
    final filtered = _filtered;
    final selectedVisible = _selectedMachineId != null &&
        filtered.any((m) => m.id == _selectedMachineId);
    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 320, child: _buildListPanel()),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: selectedVisible && _showForm
                ? _buildFormPanel()
                : selectedVisible
                    ? _buildDetailPanel()
                    : const Center(child: Text('Selecciona una máquina')),
          ),
        ],
      ),
    );
  }

  Widget _buildListPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Buscar máquina...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        _buildDatePickerRow(),
        if (_loadingList)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView.separated(
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = _filtered[i];
                return ListTile(
                  selected: m.id == _selectedMachineId,
                  title: Text(m.name),
                  subtitle: Text(m.locationName ?? ''),
                  trailing: m.inspected != null
                      ? InspectionChip(inspected: m.inspected!)
                      : null,
                  onTap: () => _selectMachine(m.id),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDetailPanel() {
    if (_selectedMachineId == null) {
      return const Center(child: Text('Selecciona una máquina'));
    }
    return FutureBuilder<Machine>(
      future: _detailFuture,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final machine = snap.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(machine.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              _InfoRow('Local', machine.locationName ?? '-'),
              _InfoRow('Tickets redemption', machine.hasRedemptionTickets ? 'Sí' : 'No'),
              Row(children: [
                const Text('Estado: '),
                StatusBadge(status: machine.lastStatus),
              ]),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar inspección'),
                onPressed: () => setState(() => _showForm = true),
              ),
              const SizedBox(height: 24),
              Text('Últimas inspecciones',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (machine.inspections.isEmpty)
                const Text('Sin inspecciones previas')
              else
                ...machine.inspections.map((i) => _InspectionTile(
                      inspection: i,
                      role: _role,
                      currentUserId: _userId,
                      onEdit: () => context.push(
                        '/machines/${machine.id}/inspect',
                        extra: {
                          'hasRedemptionTickets': machine.hasRedemptionTickets,
                          'inspection': i,
                        },
                      ).then((_) => setState(() {
                            _detailFuture = widget.api.getMachineById(_selectedMachineId!);
                            _partsFuture = widget.api.getSpareParts(machineId: _selectedMachineId!);
                          })),
                    )),
              const SizedBox(height: 32),
              Text('Repuestos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              FutureBuilder<List<SparePart>>(
                future: _partsFuture,
                builder: (context, partsSnap) {
                  if (_partsFuture == null || partsSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (partsSnap.hasError) return Text('Error: ${partsSnap.error}');
                  final parts = partsSnap.data ?? [];
                  if (parts.isEmpty) return const Text('Sin repuestos');
                  return Column(
                    children: [
                      ...parts.map((p) => _SparePartTile(
                            part: p,
                            role: _role,
                            onEdit: () => context.push(
                              '/repuestos/${p.id}/edit',
                              extra: {'sparePart': p},
                            ).then((_) => setState(() {
                                  _partsFuture = widget.api.getSpareParts(machineId: _selectedMachineId!);
                                })),
                            onDelete: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Eliminar repuesto'),
                                  content: Text('¿Eliminar "${p.description}"?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
                                  ],
                                ),
                              );
                              if (ok == true && mounted) {
                                await widget.api.deleteSparePart(p.id);
                                if (mounted) setState(() { _partsFuture = widget.api.getSpareParts(machineId: _selectedMachineId!); });
                              }
                            },
                          )),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Añadir repuesto'),
                onPressed: () => context.push(
                  '/repuestos/new',
                  extra: {'machineId': machine.id},
                ).then((_) => setState(() {
                      _partsFuture = widget.api.getSpareParts(machineId: _selectedMachineId!);
                    })),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFormPanel() {
    final selectedMachine = _machines.firstWhere((m) => m.id == _selectedMachineId);
    return _InspectionPanel(
      api: widget.api,
      machineId: _selectedMachineId!,
      hasRedemptionTickets: selectedMachine.hasRedemptionTickets,
      onSubmitted: () => setState(() {
        _showForm = false;
        _detailFuture = widget.api.getMachineById(_selectedMachineId!);
      }),
      onCancel: () => setState(() => _showForm = false),
    );
  }

}

// ── Helper widgets ───────────────────────────────────────────────────────────

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

  const _InspectionTile({
    required this.inspection,
    this.role,
    this.currentUserId,
    this.onEdit,
  });

  bool _canEdit() {
    if (role == null) return false;
    if (role == 'admin') return true;
    final today = DateTime.now();
    final d = inspection.inspectedAt;
    final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
    return isToday && inspection.technicianId == currentUserId;
  }

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${inspection.inspectedAt.day}/${inspection.inspectedAt.month}/${inspection.inspectedAt.year}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_canEdit())
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Editar inspección',
                onPressed: onEdit,
              ),
          ],
        ),
      ),
    );
  }
}

class _SparePartTile extends StatelessWidget {
  final SparePart part;
  final String? role;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SparePartTile({
    required this.part,
    required this.role,
    required this.onEdit,
    required this.onDelete,
  });

  Color _statusColor() => switch (part.status) {
        'pedido'   => Colors.blue,
        'recibido' => Colors.green,
        _          => Colors.orange,
      };

  String _statusLabel() => switch (part.status) {
        'pedido'   => 'Pedido',
        'recibido' => 'Recibido',
        _          => 'Pendiente',
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
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: onEdit),
            if (role == 'admin')
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar', onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

// ── Inline inspection form for desktop panel ─────────────────────────────────

class _InspectionPanel extends StatefulWidget {
  final ApiClient api;
  final String machineId;
  final bool hasRedemptionTickets;
  final VoidCallback onSubmitted;
  final VoidCallback onCancel;

  const _InspectionPanel({
    required this.api,
    required this.machineId,
    required this.hasRedemptionTickets,
    required this.onSubmitted,
    required this.onCancel,
  });

  @override
  State<_InspectionPanel> createState() => _InspectionPanelState();
}

class _InspectionPanelState extends State<_InspectionPanel> {
  final _commentCtrl = TextEditingController();
  String _status = 'operative';
  bool _cardReaderOk = true;
  String _failureType = 'no_lee';
  bool _dispenserOk = true;
  String _ticketLevel = 'full';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'machine_id': widget.machineId,
        'status': _status,
        'card_reader_ok': _cardReaderOk,
        if (!_cardReaderOk) 'card_reader_failure_type': _failureType,
        if (_commentCtrl.text.trim().isNotEmpty) 'comment': _commentCtrl.text.trim(),
        if (widget.hasRedemptionTickets)
          'ticket_check': {'dispenser_ok': _dispenserOk, 'ticket_level': _ticketLevel},
      };
      await widget.api.createInspection(data);
      if (mounted) widget.onSubmitted();
    } catch (_) {
      if (mounted) setState(() { _error = 'Error al guardar. Reinténtalo.'; });
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Registrar inspección',
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
              TextButton(onPressed: widget.onCancel, child: const Text('Cancelar')),
            ],
          ),
          const SizedBox(height: 16),
          Text('Estado', style: Theme.of(context).textTheme.titleSmall),
          ..._statusOptions.map((opt) => RadioListTile<String>(
                title: Text(opt.$2),
                value: opt.$1,
                groupValue: _status,
                onChanged: (v) => setState(() => _status = v!),
              )),
          const Divider(),
          Text('Lector de tarjetas', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Funciona correctamente'),
            value: _cardReaderOk,
            onChanged: (v) => setState(() => _cardReaderOk = v),
          ),
          if (!_cardReaderOk) ...[
            Text('Tipo de fallo', style: Theme.of(context).textTheme.titleSmall),
            ..._failureTypes.map((opt) => RadioListTile<String>(
                  title: Text(opt.$2),
                  value: opt.$1,
                  groupValue: _failureType,
                  onChanged: (v) => setState(() => _failureType = v!),
                )),
          ],
          if (widget.hasRedemptionTickets) ...[
            const Divider(),
            Text('Tickets redemption', style: Theme.of(context).textTheme.titleSmall),
            SwitchListTile(
              title: const Text('Dispensador OK'),
              value: _dispenserOk,
              onChanged: (v) => setState(() => _dispenserOk = v),
            ),
            Text('Nivel de tickets', style: Theme.of(context).textTheme.titleSmall),
            ..._ticketLevels.map((opt) => RadioListTile<String>(
                  title: Text(opt.$2),
                  value: opt.$1,
                  groupValue: _ticketLevel,
                  onChanged: (v) => setState(() => _ticketLevel = v!),
                )),
          ],
          const Divider(),
          TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(
              labelText: 'Comentario del técnico',
              hintText: 'Observaciones adicionales...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Guardar inspección'),
          ),
        ],
      ),
    );
  }
}
