import 'package:flutter/material.dart';
import '../models/location.dart';
import '../models/machine.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/desktop_shell_scope.dart';

class AdminScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const AdminScreen({super.key, required this.api, required this.storage});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with TickerProviderStateMixin {
  late final TabController _tabController;
  List<Location> _locations = [];
  List<Machine> _machines = [];
  List<User> _users = [];
  String? _currentUserId;
  bool _loading = true;
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final locFuture   = widget.api.getLocations();
    final machFuture  = widget.api.getMachines(includeInactive: _showInactive);
    final usersFuture = widget.api.getUsers();
    final idFuture    = widget.storage.getUserId();
    final locs        = await locFuture;
    final machines    = await machFuture;
    final users       = await usersFuture;
    final userId      = await idFuture;
    if (!mounted) return;
    setState(() {
      _locations     = locs;
      _machines      = machines;
      _users         = users;
      _currentUserId = userId;
      _loading       = false;
    });
  }

  Future<void> _showLocationDialog({Location? location}) async {
    final nameCtrl = TextEditingController(text: location?.name ?? '');
    final addrCtrl = TextEditingController(text: location?.address ?? '');
    final formKey  = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(location == null ? 'Nueva ubicación' : 'Editar ubicación'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: addrCtrl,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      nameCtrl.dispose();
      addrCtrl.dispose();
      return;
    }

    final name    = nameCtrl.text.trim();
    final address = addrCtrl.text.trim();
    nameCtrl.dispose();
    addrCtrl.dispose();

    if (location == null) {
      await widget.api.createLocation(name: name, address: address.isEmpty ? null : address);
    } else {
      await widget.api.updateLocation(location.id, name: name, address: address.isEmpty ? null : address);
    }
    await _load();
  }

  Future<void> _deleteLocation(Location location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar ubicación'),
        content: Text('¿Eliminar "${location.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.deleteLocation(location.id);
    await _load();
  }

  Future<void> _showMachineDialog({Machine? machine}) async {
    final nameCtrl = TextEditingController(text: machine?.name ?? '');
    String? selectedLocationId = machine?.locationId;
    bool hasTickets = machine?.hasRedemptionTickets ?? false;
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(machine == null ? 'Nueva máquina' : 'Editar máquina'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                DropdownButtonFormField<String?>(
                  value: selectedLocationId,
                  decoration: const InputDecoration(labelText: 'Ubicación'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Sin ubicación')),
                    ..._locations.map((l) => DropdownMenuItem<String?>(
                          value: l.id,
                          child: Text(l.name),
                        )),
                  ],
                  onChanged: (v) =>
                      setDialogState(() { selectedLocationId = v; }),
                ),
                SwitchListTile(
                  title: const Text('Tickets de redención'),
                  value: hasTickets,
                  onChanged: (v) =>
                      setDialogState(() { hasTickets = v; }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      nameCtrl.dispose();
      return;
    }

    final name = nameCtrl.text.trim();
    nameCtrl.dispose();

    if (machine == null) {
      await widget.api.createMachineAdmin(
        name: name,
        locationId: selectedLocationId,
        hasRedemptionTickets: hasTickets,
      );
    } else {
      await widget.api.updateMachine(
        machine.id,
        name: name,
        locationId: selectedLocationId,
        hasRedemptionTickets: hasTickets,
      );
    }
    await _load();
  }

  Future<void> _decommissionMachine(Machine machine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dar de baja'),
        content: Text(
            '¿Dar de baja "${machine.name}"? Permanecerá en el histórico.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dar de baja'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.decommissionMachine(machine.id);
    await _load();
  }

  Future<void> _toggleRole(User user) async {
    final newRole = user.role == 'admin' ? 'technician' : 'admin';
    await widget.api.updateUserRole(user.id, newRole);
    await _load();
  }

  Widget _buildLocationTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Nueva ubicación',
              onPressed: _showLocationDialog,
            ),
          ],
        ),
        ..._locations.map((loc) => ListTile(
              title: Text(loc.name),
              subtitle: loc.address != null ? Text(loc.address!) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Editar',
                    onPressed: () => _showLocationDialog(location: loc),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Eliminar',
                    onPressed: () => _deleteLocation(loc),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildMachinesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Máquinas',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              const Text('Inactivas'),
              Switch(
                value: _showInactive,
                onChanged: (v) {
                  setState(() { _showInactive = v; });
                  _load();
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Nueva máquina',
                onPressed: () => _showMachineDialog(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: _machines
                .map((m) => ListTile(
                      title: Row(
                        children: [
                          Flexible(child: Text(m.name)),
                          if (!m.active) ...[
                            const SizedBox(width: 8),
                            const Chip(label: Text('Inactiva')),
                          ],
                        ],
                      ),
                      subtitle: m.locationName != null
                          ? Text(m.locationName!)
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Editar',
                            onPressed: () => _showMachineDialog(machine: m),
                          ),
                          TextButton(
                            key: Key('decommission-${m.id}'),
                            onPressed: m.active
                                ? () => _decommissionMachine(m)
                                : null,
                            child: const Text('Dar de baja'),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildUsersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Usuarios',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._users.map((user) {
          final isOwn = user.id == _currentUserId;
          return ListTile(
            title: Text(user.name),
            subtitle: Text(user.email),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(user.role == 'admin' ? 'Admin' : 'Técnico'),
                  backgroundColor: user.role == 'admin'
                      ? Colors.indigo[100]
                      : Colors.grey[200],
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: Key('role-toggle-${user.id}'),
                  onPressed: isOwn ? null : () => _toggleRole(user),
                  child: Text(user.role == 'admin'
                      ? 'Revocar admin'
                      : 'Hacer admin'),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  static const _tabs = [
    Tab(text: 'Ubicaciones'),
    Tab(text: 'Máquinas'),
    Tab(text: 'Usuarios'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text('Administración'),
              bottom: TabBar(controller: _tabController, tabs: _tabs),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (isDesktop)
                  TabBar(controller: _tabController, tabs: _tabs),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLocationTab(),
                      _buildMachinesTab(),
                      _buildUsersTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
