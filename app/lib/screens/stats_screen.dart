import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:dio/dio.dart';
import '../services/api_client.dart';
import '../models/location.dart';
import '../models/stats.dart';
import '../utils/download_file.dart';
import '../widgets/desktop_shell_scope.dart';

enum _Period { d7, d15, d30, custom }

extension _PeriodLabel on _Period {
  String get label => switch (this) {
    _Period.d7     => '7d',
    _Period.d15    => '15d',
    _Period.d30    => '30d',
    _Period.custom => 'Personalizado',
  };

  DateTimeRange? get defaultRange {
    final today = DateTime.now();
    final start = switch (this) {
      _Period.d7     => today.subtract(const Duration(days: 7)),
      _Period.d15    => today.subtract(const Duration(days: 15)),
      _Period.d30    => today.subtract(const Duration(days: 30)),
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
  String? _success;

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
    if (mounted) setState(() { _loading = true; _error = null; _success = null; });
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
    if (mounted) setState(() { _loading = true; _error = null; _success = null; });
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
    if (mounted) setState(() { _loading = true; _error = null; _success = null; });
    try {
      await widget.api.sendStatsByEmail(
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      if (mounted) setState(() => _success = 'Estadísticas enviadas correctamente');
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        final errorCode = e.response?.data?['error'];
        if (mounted) {
          setState(() => _error = errorCode == 'sin_destinatarios'
              ? 'No hay destinatarios configurados. Ve a Ajustes para añadirlos.'
              : 'No hay registros para el período seleccionado');
        }
      } else {
        if (mounted) setState(() => _error = 'Error al enviar las estadísticas');
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

  Widget _buildSummaryRow() {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            title: 'MTTR (Tiempo Medio de Reparación)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _stats!.mttrHours != null
                      ? '${_stats!.mttrHours!.toStringAsFixed(1)} h'
                      : '—',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (_stats!.mttrMedianHours != null)
                  Text(
                    'Media: ${_stats!.mttrMedianHours!.toStringAsFixed(1)} h',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            title: 'Total máquinas',
            child: Text(
              '${_stats!.totalMachines}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendChart() {
    final data = _stats!.dailyBreakdown;
    return _MetricCard(
      title: 'Tendencia de inspecciones',
      child: data.isEmpty
          ? const Center(child: Text('Sin datos en el período'))
          : SizedBox(
              height: 180,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: (data.length * 28.0).clamp(200.0, double.infinity),
                  child: BarChart(
                    BarChartData(
                      barGroups: data.asMap().entries.map((e) {
                        final idx = e.key;
                        final day = e.value;
                        final total = (day.operative + day.outOfService + day.inRepair).toDouble();
                        if (total == 0) {
                          return BarChartGroupData(x: idx, barRods: [
                            BarChartRodData(toY: 0, width: 18),
                          ]);
                        }
                        final op = day.operative.toDouble();
                        final oos = day.outOfService.toDouble();
                        final ir = day.inRepair.toDouble();
                        return BarChartGroupData(
                          x: idx,
                          barRods: [
                            BarChartRodData(
                              toY: total,
                              width: 18,
                              rodStackItems: [
                                BarChartRodStackItem(0, op, Colors.green[600]!),
                                BarChartRodStackItem(op, op + oos, Colors.red[600]!),
                                BarChartRodStackItem(op + oos, op + oos + ir, Colors.orange[600]!),
                              ],
                            ),
                          ],
                        );
                      }).toList(),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                              final showEvery = data.length > 15 ? 5 : 1;
                              if (idx % showEvery != 0) return const SizedBox.shrink();
                              final d = data[idx].date;
                              return Text(
                                '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 9),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) => Text(
                              value.toInt().toString(),
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData:   const FlGridData(show: true),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCardReaderCard() {
    final cr = _stats!.cardReaderStats;
    return _MetricCard(
      title: 'Lector de tarjeta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: cr.pctOk / 100,
              color: Colors.green[600],
              backgroundColor: Colors.red[100],
              minHeight: 14,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('✓ OK: ${cr.pctOk.toStringAsFixed(1)}%',
                  style: TextStyle(color: Colors.green[700], fontSize: 13)),
              Text('✗ Fallo: ${cr.pctFail.toStringAsFixed(1)}%',
                  style: TextStyle(color: Colors.red[700], fontSize: 13)),
            ],
          ),
          if (cr.topFailureType != null) ...[
            const SizedBox(height: 4),
            Text(
              'Fallo más frecuente: ${cr.topFailureType}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDispenserCard() {
    final d = _stats!.dispenserStats;
    return _MetricCard(
      title: 'Dispensador de tickets',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: d.pctOk / 100,
              color: Colors.green[600],
              backgroundColor: Colors.green[50],
              minHeight: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text('✓ OK: ${d.pctOk.toStringAsFixed(1)}%',
              style: TextStyle(color: Colors.green[700], fontSize: 13)),
          if (d.pctNoCheck > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Sin registro: ${d.pctNoCheck.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (d.pctFull > 0)
                Chip(
                  label: Text('Lleno: ${d.pctFull.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.green[100],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
              if (d.pctLow > 0)
                Chip(
                  label: Text('Bajo: ${d.pctLow.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.orange[100],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
              if (d.pctEmpty > 0)
                Chip(
                  label: Text('Vacío: ${d.pctEmpty.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.red[100],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityChart() {
    final operative = _stats!.pctOperative;
    final outOfService = _stats!.pctOutOfService;
    final inRepair = _stats!.pctInRepair;
    final hasData = operative > 0 || outOfService > 0 || inRepair > 0;

    return _MetricCard(
      title: 'Disponibilidad',
      child: hasData
          ? Column(
              children: [
                SizedBox(
                  height: 160,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 0,
                      sections: [
                        if (operative > 0)
                          PieChartSectionData(
                            value: operative,
                            color: Colors.green[600]!,
                            title: '${operative.toStringAsFixed(0)}%',
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                            radius: 75,
                          ),
                        if (outOfService > 0)
                          PieChartSectionData(
                            value: outOfService,
                            color: Colors.red[600]!,
                            title: '${outOfService.toStringAsFixed(0)}%',
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                            radius: 75,
                          ),
                        if (inRepair > 0)
                          PieChartSectionData(
                            value: inRepair,
                            color: Colors.orange[600]!,
                            title: '${inRepair.toStringAsFixed(0)}%',
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                            radius: 75,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _LegendItem(
                    color: Colors.green[600]!,
                    label: 'Operativa',
                    value: operative),
                _LegendItem(
                    color: Colors.red[600]!,
                    label: 'Fuera de servicio',
                    value: outOfService),
                _LegendItem(
                    color: Colors.orange[600]!,
                    label: 'En reparación',
                    value: inRepair),
              ],
            )
          : const Center(child: Text('Sin datos')),
    );
  }

  Widget _buildTopProblematic() {
    final machines = _stats!.topProblematic;
    if (machines.isEmpty) {
      return const _MetricCard(
        title: 'Top 5 problemáticas',
        child: Text('Sin averías en el período'),
      );
    }
    final maxCount = machines.first.faultCount;
    return _MetricCard(
      title: 'Top 5 problemáticas',
      child: Column(
        children: machines.map((m) {
          final name = m.name.length > 15 ? '${m.name.substring(0, 15)}…' : m.name;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxCount > 0 ? m.faultCount / maxCount : 0,
                      color: Colors.red[400],
                      backgroundColor: Colors.red[50],
                      minHeight: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${m.faultCount}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMttrTopMachines() {
    final machines = _stats!.mttrTopMachines;
    if (machines.isEmpty) {
      return const _MetricCard(
        title: 'Top 5 reparaciones más lentas',
        child: Text('Sin datos suficientes'),
      );
    }
    final maxHours = machines.first.avgHours;
    return _MetricCard(
      title: 'Top 5 reparaciones más lentas',
      child: Column(
        children: machines.map((m) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  child: Text(m.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxHours > 0 ? m.avgHours / maxHours : 0,
                      color: Colors.orange[400],
                      backgroundColor: Colors.orange[50],
                      minHeight: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${m.avgHours.toStringAsFixed(1)} h',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCharts(bool isDesktop) {
    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildAvailabilityChart()),
              const SizedBox(width: 12),
              Expanded(child: _buildTopProblematic()),
            ],
          ),
          const SizedBox(height: 12),
          _buildMttrTopMachines(),
          const SizedBox(height: 12),
          _buildTrendChart(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCardReaderCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildDispenserCard()),
            ],
          ),
        ],
      );
    }
    return Column(
      children: [
        _buildAvailabilityChart(),
        const SizedBox(height: 12),
        _buildTopProblematic(),
        const SizedBox(height: 12),
        _buildMttrTopMachines(),
        const SizedBox(height: 12),
        _buildTrendChart(),
        const SizedBox(height: 12),
        _buildCardReaderCard(),
        const SizedBox(height: 12),
        _buildDispenserCard(),
      ],
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
            if (_success != null) ...[
              const SizedBox(height: 12),
              Text(_success!, style: const TextStyle(color: Colors.green)),
            ],
            if (_stats != null) ...[
              const SizedBox(height: 8),
              _buildSummaryRow(),
              const SizedBox(height: 12),
              _buildCharts(isDesktop),
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

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final double value;
  const _LegendItem(
      {required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text('${value.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
