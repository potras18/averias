import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/spare_part.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class SparePartsScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const SparePartsScreen({super.key, required this.api, required this.storage});

  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen> {
  String? _statusFilter;
  late Future<List<SparePart>> _future;
  String? _role;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getSpareParts();
    widget.storage.getRole().then((r) { if (mounted) setState(() => _role = r); });
  }

  void _reload() => setState(() {
        _future = widget.api.getSpareParts(status: _statusFilter);
      });

  Future<void> _confirmDelete(SparePart part) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar repuesto'),
        content: Text('¿Eliminar "${part.description}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await widget.api.deleteSparePart(part.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Repuestos')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/repuestos/new').then((_) => _reload()),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in [
                    ('Todos', null),
                    ('Pendiente', 'pendiente'),
                    ('Pedido', 'pedido'),
                    ('Recibido', 'recibido'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.$1),
                        selected: _statusFilter == entry.$2,
                        onSelected: (_) => setState(() {
                          _statusFilter = entry.$2;
                          _future = widget.api.getSpareParts(status: entry.$2);
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<SparePart>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                final parts = snap.data!;
                if (parts.isEmpty) return const Center(child: Text('Sin repuestos'));
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: parts.length,
                  itemBuilder: (_, i) => _SparePartTile(
                    part: parts[i],
                    role: _role,
                    onEdit: () => context
                        .push('/repuestos/${parts[i].id}/edit',
                            extra: {'sparePart': parts[i]})
                        .then((_) => _reload()),
                    onDelete: () => _confirmDelete(parts[i]),
                  ),
                );
              },
            ),
          ),
        ],
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(part.machineName, style: Theme.of(context).textTheme.bodySmall),
            Text('Cantidad: ${part.quantity}  ·  ${part.createdByName}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        isThreeLine: true,
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
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Eliminar',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
