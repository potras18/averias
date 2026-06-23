// averias/app/lib/screens/inspection_form_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../widgets/desktop_shell_scope.dart';

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

class InspectionFormScreen extends StatefulWidget {
  final ApiClient api;
  final String machineId;
  final bool hasRedemptionTickets;

  const InspectionFormScreen({
    super.key,
    required this.api,
    required this.machineId,
    this.hasRedemptionTickets = false,
  });

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
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
    setState(() { _saving = true; _error = null; });
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
      if (mounted) context.pop();
    } catch (_) {
      setState(() { _error = 'Error al guardar. Reinténtalo.'; });
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    if (isDesktop) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.edit_note, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Usa la app móvil para registrar inspecciones',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar inspección')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
            child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Guardar inspección'),
          ),
        ],
      ),
    );
  }
}
