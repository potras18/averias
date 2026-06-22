import 'package:flutter/material.dart';
import '../models/location.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class AdminScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const AdminScreen({super.key, required this.api, required this.storage});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Location> _locations = [];
  List<User> _users = [];
  String? _currentUserId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final locFuture  = widget.api.getLocations();
    final usersFuture = widget.api.getUsers();
    final idFuture   = widget.storage.getUserId();
    final locs   = await locFuture;
    final users  = await usersFuture;
    final userId = await idFuture;
    if (!mounted) return;
    setState(() {
      _locations     = locs;
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
      await widget.api.createLocation(
        name: name,
        address: address.isEmpty ? null : address,
      );
    } else {
      await widget.api.updateLocation(
        location.id,
        name: name,
        address: address.isEmpty ? null : address,
      );
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

  Future<void> _toggleRole(User user) async {
    final newRole = user.role == 'admin' ? 'technician' : 'admin';
    await widget.api.updateUserRole(user.id, newRole);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Ubicaciones ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Ubicaciones',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Nueva ubicación',
                onPressed: _showLocationDialog,
              ),
            ],
          ),
          ..._locations.map(
            (loc) => ListTile(
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
            ),
          ),
          const Divider(height: 32),
          // ── Usuarios ──
          const Text(
            'Usuarios',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
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
                    child: Text(
                        user.role == 'admin' ? 'Revocar admin' : 'Hacer admin'),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
