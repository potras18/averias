import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

const _machineProblems = [
  ('no_enciende', 'No enciende'),
  ('no_acepta_pago', 'No acepta pago'),
  ('pantalla', 'Problema de pantalla'),
  ('mecanico', 'Ruido o problema mecánico'),
  ('no_entrega_premio', 'No entrega premio'),
  ('otro', 'Otro'),
];

const _cardProblems = [
  ('no_lee', 'No lee la tarjeta'),
  ('error_comunicacion', 'Error de comunicación'),
  ('dano_fisico', 'Daño físico'),
  ('otro', 'Otro'),
];

class IncidenciaFormScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  const IncidenciaFormScreen({super.key, required this.api, required this.storage});

  @override
  State<IncidenciaFormScreen> createState() => _IncidenciaFormScreenState();
}

class _IncidenciaFormScreenState extends State<IncidenciaFormScreen> {
  late Future<List<Machine>> _machinesFuture;
  final _commentCtrl = TextEditingController();
  String? _machineId;
  String? _machineProblem;
  String? _cardProblem;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _machinesFuture = widget.api.getMachines();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (_) {}
    await widget.storage.clear();
    if (mounted) context.go('/login');
  }

  Future<void> _submit() async {
    if (_machineId == null) {
      setState(() => _error = 'Selecciona una máquina');
      return;
    }
    if (_machineProblem == null && _cardProblem == null) {
      setState(() => _error = 'Indica al menos un problema (máquina o lector)');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.createIncidencia(
        machineId: _machineId!,
        machineProblemType: _machineProblem,
        cardReaderProblemType: _cardProblem,
        comment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _machineId = null;
        _machineProblem = null;
        _cardProblem = null;
        _commentCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aviso enviado. ¡Gracias!')),
      );
    } catch (e) {
      setState(() => _error = 'No se pudo enviar el aviso. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar avería'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Cerrar sesión', onPressed: _logout),
        ],
      ),
      body: FutureBuilder<List<Machine>>(
        future: _machinesFuture,
        builder: (context, snap) {
          if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error al cargar máquinas: ${snap.error}'));
          }
          final machines = snap.data ?? [];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text('Selecciona la máquina y describe el problema.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _machineId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Máquina'),
                    items: machines
                        .map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _machineId = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _machineProblem,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Problema de la máquina'),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('Ninguno')),
                      ..._machineProblems.map((p) => DropdownMenuItem(value: p.$1, child: Text(p.$2))),
                    ],
                    onChanged: (v) => setState(() => _machineProblem = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _cardProblem,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Problema del lector de tarjetas'),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('Ninguno')),
                      ..._cardProblems.map((p) => DropdownMenuItem(value: p.$1, child: Text(p.$2))),
                    ],
                    onChanged: (v) => setState(() => _cardProblem = v),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _commentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Comentario (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.send),
                    label: const Text('Enviar aviso'),
                    onPressed: _saving ? null : _submit,
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
