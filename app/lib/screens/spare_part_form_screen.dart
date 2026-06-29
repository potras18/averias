import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/spare_part.dart';
import '../models/machine.dart';
import '../services/api_client.dart';

class SparePartFormScreen extends StatefulWidget {
  final ApiClient api;
  final SparePart? sparePart;
  final String? preselectedMachineId;

  const SparePartFormScreen({
    super.key,
    required this.api,
    this.sparePart,
    this.preselectedMachineId,
  });

  @override
  State<SparePartFormScreen> createState() => _SparePartFormScreenState();
}

class _SparePartFormScreenState extends State<SparePartFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descCtrl;
  late final TextEditingController _qtyCtrl;
  String? _machineId;
  String _status = 'pendiente';
  bool _loading = false;
  late Future<List<Machine>> _machinesFuture;

  bool get _isEdit => widget.sparePart != null;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.sparePart?.description ?? '');
    _qtyCtrl  = TextEditingController(text: '${widget.sparePart?.quantity ?? 1}');
    _machineId = widget.sparePart?.machineId ?? widget.preselectedMachineId;
    _status    = widget.sparePart?.status ?? 'pendiente';
    _machinesFuture = widget.api.getMachines();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_machineId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona una máquina')));
      return;
    }
    setState(() => _loading = true);
    try {
      if (!_isEdit) {
        await widget.api.createSparePart(
          machineId: _machineId!,
          description: _descCtrl.text.trim(),
          quantity: int.parse(_qtyCtrl.text),
        );
      } else {
        await widget.api.updateSparePart(
          widget.sparePart!.id,
          description: _descCtrl.text.trim(),
          quantity: int.parse(_qtyCtrl.text),
          status: _status,
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Editar repuesto' : 'Nuevo repuesto')),
      body: FutureBuilder<List<Machine>>(
        future: _machinesFuture,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final machines = snap.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: _machineId,
                    decoration: const InputDecoration(labelText: 'Máquina'),
                    items: machines
                        .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                        .toList(),
                    onChanged: _isEdit ? null : (v) => setState(() => _machineId = v),
                    validator: (v) => v == null ? 'Obligatorio' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                        labelText: '¿Qué repuesto hay que comprar?'),
                    maxLines: 3,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _qtyCtrl,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1) return 'Mínimo 1';
                      return null;
                    },
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Estado'),
                      items: const [
                        DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
                        DropdownMenuItem(value: 'pedido',    child: Text('Pedido')),
                        DropdownMenuItem(value: 'recibido',  child: Text('Recibido')),
                      ],
                      onChanged: (v) => setState(() => _status = v!),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isEdit ? 'Guardar cambios' : 'Crear solicitud'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
