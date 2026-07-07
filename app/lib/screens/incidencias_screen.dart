import 'package:flutter/material.dart';
import '../models/incidencia.dart';
import '../services/api_client.dart';

const _machineProblemLabels = {
  'no_enciende': 'No enciende',
  'no_acepta_pago': 'No acepta pago',
  'pantalla': 'Problema de pantalla',
  'mecanico': 'Ruido o problema mecánico',
  'no_entrega_premio': 'No entrega premio',
  'otro': 'Otro',
};

const _cardProblemLabels = {
  'no_lee': 'Lector: no lee',
  'error_comunicacion': 'Lector: error de comunicación',
  'dano_fisico': 'Lector: daño físico',
  'otro': 'Lector: otro',
};

String _fmt(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

class IncidenciasScreen extends StatefulWidget {
  final ApiClient api;
  const IncidenciasScreen({super.key, required this.api});

  @override
  State<IncidenciasScreen> createState() => _IncidenciasScreenState();
}

class _IncidenciasScreenState extends State<IncidenciasScreen> {
  String _status = 'open';
  late Future<List<Incidencia>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.api.getIncidencias(status: _status);
  }

  void _setStatus(String s) => setState(() {
        _status = s;
        _reload();
      });

  Future<void> _resolve(Incidencia inc) async {
    final result = await showDialog<({String resolution, String? comment})>(
      context: context,
      builder: (ctx) => _ResolveDialog(incidencia: inc),
    );
    if (result == null) return;
    try {
      await widget.api.resolveIncidencia(inc.id, resolution: result.resolution, comment: result.comment);
      if (mounted) setState(_reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo resolver el aviso')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Incidencias')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Abiertas'),
                  selected: _status == 'open',
                  onSelected: (_) => _setStatus('open'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Resueltas'),
                  selected: _status == 'resolved',
                  onSelected: (_) => _setStatus('resolved'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Incidencia>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return Center(
                    child: Text(_status == 'open' ? 'No hay incidencias abiertas' : 'No hay incidencias resueltas'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _IncidenciaCard(
                    incidencia: items[i],
                    onResolve: () => _resolve(items[i]),
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

class _IncidenciaCard extends StatelessWidget {
  final Incidencia incidencia;
  final VoidCallback onResolve;
  const _IncidenciaCard({required this.incidencia, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final inc = incidencia;
    final problems = <String>[
      if (inc.machineProblemType != null) _machineProblemLabels[inc.machineProblemType] ?? inc.machineProblemType!,
      if (inc.cardReaderProblemType != null) _cardProblemLabels[inc.cardReaderProblemType] ?? inc.cardReaderProblemType!,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    inc.machineName ?? inc.machineId,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (inc.status == 'open')
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Resolver'),
                    onPressed: onResolve,
                  )
                else
                  Chip(
                    label: Text(inc.resolution == 'operative' ? 'Funcionando' : 'En reparación'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(inc.locationName ?? '—', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: problems.map((p) => Chip(label: Text(p), visualDensity: VisualDensity.compact)).toList(),
            ),
            if (inc.comment != null && inc.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(inc.comment!),
            ],
            const SizedBox(height: 8),
            Text(
              'Reportado ${_fmt(inc.createdAt)}${inc.reportedByName != null ? ' · ${inc.reportedByName}' : ''}'
              '${inc.resolvedAt != null ? '  →  Resuelto ${_fmt(inc.resolvedAt!)}' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolveDialog extends StatefulWidget {
  final Incidencia incidencia;
  const _ResolveDialog({required this.incidencia});

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  String _resolution = 'operative';
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resolver incidencia'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(
            value: 'operative',
            groupValue: _resolution,
            title: const Text('Funcionando (operativa)'),
            onChanged: (v) => setState(() => _resolution = v!),
          ),
          RadioListTile<String>(
            value: 'in_repair',
            groupValue: _resolution,
            title: const Text('En reparación'),
            onChanged: (v) => setState(() => _resolution = v!),
          ),
          TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(labelText: 'Comentario (opcional)'),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (resolution: _resolution, comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim()),
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
