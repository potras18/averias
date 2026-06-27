import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../models/location.dart';
import '../models/stats.dart';
import '../utils/download_file.dart';
import '../widgets/desktop_shell_scope.dart';

enum _Period { d7, d30, d90, custom }

extension _PeriodLabel on _Period {
  String get label => switch (this) {
    _Period.d7 => '7d',
    _Period.d30 => '30d',
    _Period.d90 => '90d',
    _Period.custom => 'Personalizado',
  };

  DateTimeRange? get defaultRange {
    final today = DateTime.now();
    final start = switch (this) {
      _Period.d7 => today.subtract(const Duration(days: 7)),
      _Period.d30 => today.subtract(const Duration(days: 30)),
      _Period.d90 => today.subtract(const Duration(days: 90)),
      _Period.custom => null,
    };
    if (start == null) return null;
    return DateTimeRange(start: start, end: today);
  }
}

class StatsScreen extends StatefulWidget {
  final ApiClient api;
  const StatsScreen({super.key, required this.api});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _Period _period = _Period.d30;
  DateTimeRange? _customRange;
  String? _selectedLocationId;
  List<Location> _locations = [];
  StatsResult? _stats;
  bool _loading = false;
  String? _error;

  DateTimeRange? get _activeRange =>
      _period == _Period.custom ? _customRange : _period.defaultRange;

  String? get _fromStr =>
      _activeRange?.start.toIso8601String().substring(0, 10);

  String? get _toStr =>
      _activeRange?.end.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _loadStats();
  }

  Future<void> _loadLocations() async {
    try {
      final locs = await widget.api.getLocations();
      if (mounted) setState(() => _locations = locs);
    } catch (_) {}
  }

  Future<void> _loadStats() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final stats = await widget.api.getStats(
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      if (mounted) setState(() => _error = 'Error al cargar estadísticas');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPeriod(_Period p) async {
    if (p == _Period.custom) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: _customRange ?? _period.defaultRange,
        locale: const Locale('es', 'ES'),
      );
      if (range == null || !mounted) return;
      setState(() { _period = _Period.custom; _customRange = range; });
    } else {
      setState(() => _period = p);
    }
    _loadStats();
  }

  Future<void> _generatePdf() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final bytes = await widget.api.getStatsPdf(
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      await downloadFile(bytes, 'estadisticas.pdf');
    } on UnsupportedError {
      if (mounted) setState(() => _error = 'Descarga no disponible en esta plataforma');
    } catch (_) {
      if (mounted) setState(() => _error = 'Error al generar PDF');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendByEmail() async {
    final emailCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enviar por email'),
        content: TextField(
          controller: emailCtrl,
          decoration: const InputDecoration(
            labelText: 'Email(s), separados por coma',
          ),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    final emailText = emailCtrl.text;
    emailCtrl.dispose();
    if (confirmed != true) return;
    final emails = emailText
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (emails.isEmpty) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await widget.api.sendStatsByEmail(
        emails: emails,
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estadísticas enviadas correctamente')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Error al enviar las estadísticas');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildPeriodChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _Period.values.map((p) => ChoiceChip(
        label: Text(p.label),
        selected: _period == p,
        onSelected: (_) => _selectPeriod(p),
      )).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    return Scaffold(
      appBar: isDesktop ? null : AppBar(title: const Text('Estadísticas')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPeriodChips(),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedLocationId,
              decoration: const InputDecoration(labelText: 'Local (opcional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos los locales')),
                ..._locations.map(
                  (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
                ),
              ],
              onChanged: (v) {
                if (mounted) setState(() => _selectedLocationId = v);
                _loadStats();
              },
            ),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_stats != null) ...[
              const SizedBox(height: 8),
              // Charts added in Task 2 — for now keep existing text cards
              _MetricCard(
                title: 'MTTR',
                child: Text(
                  _stats!.mttrHours != null
                      ? '${_stats!.mttrHours!.toStringAsFixed(1)} h'
                      : 'Sin datos suficientes',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'Disponibilidad',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_stats!.pctOperative.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    _StatusRow('Operativo', _stats!.pctOperative),
                    _StatusRow('Fuera de servicio', _stats!.pctOutOfService),
                    _StatusRow('En reparación', _stats!.pctInRepair),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'Top 5 problemáticas',
                child: _stats!.topProblematic.isEmpty
                    ? const Text('Sin datos')
                    : Column(
                        children: _stats!.topProblematic
                            .asMap()
                            .entries
                            .map((e) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Text('${e.key + 1}. ',
                                          style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Expanded(child: Text(e.value.name)),
                                      Text('${e.value.faultCount} averías'),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Generar PDF'),
                    onPressed: _loading ? null : _generatePdf,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.email),
                    label: const Text('Enviar por email'),
                    onPressed: _loading ? null : _sendByEmail,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _MetricCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final double pct;
  const _StatusRow(this.label, this.pct);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text('${pct.toStringAsFixed(1)}%')],
    );
  }
}
