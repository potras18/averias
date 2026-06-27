# Statistics Screen — Charts & Auto-load Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual "Consultar" flow in the Statistics screen with an auto-loading dashboard showing a pie chart and horizontal bar chart, filtered by quick period chips (7d / 30d / 90d / Personalizado).

**Architecture:** `StatsScreen` loads data automatically on entry (last 30 days default). Period chips replace the date picker button + Consultar button — selecting a chip immediately reloads. `fl_chart` provides the `PieChart` widget for availability breakdown; `LinearProgressIndicator` rows provide the top-5 bar visualization. Desktop uses a 2-column layout; mobile uses a single column. No backend changes.

**Tech Stack:** Flutter/Dart 3, fl_chart ^0.69.0, mocktail (tests), existing `GET /stats` endpoint.

## Global Constraints

- Flutter/Dart 3 sound null safety — no `!` on potentially-null values without null check
- `fl_chart: ^0.69.0` — use the exact version constraint
- Spanish UI copy — all user-facing strings in Spanish, matching existing app conventions
- `DesktopShellScope.of(context)?.isDesktop ?? false` — pattern for desktop detection (do not use MediaQuery for this)
- No backend changes — all data comes from the existing `GET /stats` endpoint returning `StatsResult`
- Keep existing `_generatePdf()` and `_sendByEmail()` methods intact
- `showDateRangePicker` must use `locale: const Locale('es', 'ES')`
- Tests use `mocktail` — pattern: `when(() => api.method(named: any(named: 'param')))`

---

## File Map

| File | Change |
|------|--------|
| `app/pubspec.yaml` | Add `fl_chart: ^0.69.0` |
| `app/lib/screens/stats_screen.dart` | Full rewrite — chips, auto-load, charts, responsive layout |
| `app/test/screens/stats_screen_test.dart` | Replace existing tests to match new behavior |

---

## Task 1: Period chips + auto-load (no charts yet)

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/screens/stats_screen.dart`
- Modify: `app/test/screens/stats_screen_test.dart`

**Interfaces:**
- Produces: `_Period` enum (used in Task 2), `_selectPeriod(_Period)` method, `_fromStr`/`_toStr` getters unchanged signature

---

- [ ] **Step 1: Add fl_chart to pubspec.yaml**

In `app/pubspec.yaml`, under `dependencies:`, add after the existing flutter_localizations line:

```yaml
  fl_chart: ^0.69.0
```

Run:
```bash
cd app && flutter pub get
```

Expected: resolves without error, `pubspec.lock` updated.

---

- [ ] **Step 2: Write the failing tests**

Replace the entire content of `app/test/screens/stats_screen_test.dart` with:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/stats_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/location.dart';
import 'package:averias_app/models/stats.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

class MockApiClient extends Mock implements ApiClient {}

const fakeStats = StatsResult(
  mttrHours: 4.5,
  pctOperative: 75.0,
  pctOutOfService: 15.0,
  pctInRepair: 10.0,
  totalMachines: 12,
  topProblematic: [
    TopMachine(name: 'Máquina A', faultCount: 5),
    TopMachine(name: 'Máquina B', faultCount: 2),
  ],
);

Widget _wrap(Widget child, {bool isDesktop = false}) => DesktopShellScope(
  isDesktop: isDesktop,
  child: SizedBox(
    width: isDesktop ? 1100.0 : 400.0,
    height: 800.0,
    child: MaterialApp(home: child),
  ),
);

void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    when(() => api.getLocations()).thenAnswer((_) async => [
      const Location(id: 'loc-1', name: 'Local A'),
    ]);
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => fakeStats);
  });

  testWidgets('shows period chips on init — no Consultar button', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('7d'), findsOneWidget);
    expect(find.text('30d'), findsOneWidget);
    expect(find.text('90d'), findsOneWidget);
    expect(find.text('Personalizado'), findsOneWidget);
    expect(find.text('Consultar'), findsNothing);
  });

  testWidgets('auto-loads stats on entry — calls getStats without user action', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    verify(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(1);
  });

  testWidgets('30d chip selected by default', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '30d'),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('tapping 7d chip triggers reload', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('7d'));
    await tester.pumpAndSettle();

    verify(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(2); // 1 on init + 1 on chip tap
  });

  testWidgets('shows error text when getStats throws', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenThrow(Exception('network error'));

    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Error al cargar estadísticas'), findsOneWidget);
  });

  testWidgets('PDF and email buttons visible after load', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Generar PDF'), 200);
    expect(find.text('Generar PDF'), findsOneWidget);
    expect(find.text('Enviar por email'), findsOneWidget);
  });

  testWidgets('tapping Generar PDF calls getStatsPdf', (tester) async {
    when(() => api.getStatsPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Generar PDF'), 200);
    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getStatsPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(1);
  });
}
```

---

- [ ] **Step 3: Run tests to confirm they fail**

```bash
cd app && flutter test test/screens/stats_screen_test.dart
```

Expected: multiple failures — "7d" not found, "Consultar" still found, etc.

---

- [ ] **Step 4: Rewrite stats_screen.dart — chips + auto-load**

Replace the entire content of `app/lib/screens/stats_screen.dart` with:

```dart
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
```

---

- [ ] **Step 5: Run tests**

```bash
cd app && flutter test test/screens/stats_screen_test.dart
```

Expected: all tests pass.

---

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/screens/stats_screen.dart app/test/screens/stats_screen_test.dart
git commit -m "feat: replace Consultar button with period chips and auto-load in stats screen"
```

---

## Task 2: Pie chart + horizontal bars + responsive layout

**Files:**
- Modify: `app/lib/screens/stats_screen.dart`
- Modify: `app/test/screens/stats_screen_test.dart`

**Interfaces:**
- Consumes: `_Period` enum, `StatsResult` model, `_MetricCard` widget — all from Task 1
- Produces: `_buildSummaryRow()`, `_buildAvailabilityChart()`, `_buildTopProblematic()`, `_buildBody()` — all private methods on `_StatsScreenState`

---

- [ ] **Step 1: Write failing tests for charts**

Add these tests to the `main()` block in `app/test/screens/stats_screen_test.dart` (after the existing tests, inside the same `main()` function):

```dart
  testWidgets('shows machine name from topProblematic after load', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Máquina A'), 200);
    expect(find.text('Máquina A'), findsOneWidget);
  });

  testWidgets('shows Sin averias text when topProblematic is empty', (tester) async {
    when(() => api.getStats(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => const StatsResult(
      mttrHours: null,
      pctOperative: 0,
      pctOutOfService: 0,
      pctInRepair: 0,
      totalMachines: 0,
      topProblematic: [],
    ));

    await tester.pumpWidget(_wrap(StatsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Sin averías en el período'), 200);
    expect(find.text('Sin averías en el período'), findsOneWidget);
  });

  testWidgets('desktop: shows two-column layout with Row', (tester) async {
    await tester.pumpWidget(_wrap(StatsScreen(api: api), isDesktop: true));
    await tester.pumpAndSettle();

    // Desktop layout wraps charts in a Row — verify both chart cards visible
    expect(find.text('Disponibilidad'), findsOneWidget);
    expect(find.text('Top 5 problemáticas'), findsOneWidget);
  });
```

---

- [ ] **Step 2: Run new tests to confirm they fail**

```bash
cd app && flutter test test/screens/stats_screen_test.dart
```

Expected: 'Sin averías en el período' not found, 'Disponibilidad' may not be found yet.

---

- [ ] **Step 3: Add fl_chart import and chart widgets to stats_screen.dart**

At the top of `app/lib/screens/stats_screen.dart`, add the fl_chart import after the existing imports:

```dart
import 'package:fl_chart/fl_chart.dart';
```

---

- [ ] **Step 4: Add _buildSummaryRow, _buildAvailabilityChart, _buildTopProblematic, _buildBody methods**

Add these private methods to `_StatsScreenState`, before the `build()` method:

```dart
  Widget _buildSummaryRow() {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            title: 'MTTR',
            child: Text(
              _stats!.mttrHours != null
                  ? '${_stats!.mttrHours!.toStringAsFixed(1)} h'
                  : '—',
              style: Theme.of(context).textTheme.headlineMedium,
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
      return _MetricCard(
        title: 'Top 5 problemáticas',
        child: const Text('Sin averías en el período'),
      );
    }
    final maxCount = machines.first.faultCount;
    return _MetricCard(
      title: 'Top 5 problemáticas',
      child: Column(
        children: machines.map((m) {
          final name = m.name.length > 16 ? '${m.name.substring(0, 15)}…' : m.name;
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

  Widget _buildCharts(bool isDesktop) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildAvailabilityChart()),
          const SizedBox(width: 12),
          Expanded(child: _buildTopProblematic()),
        ],
      );
    }
    return Column(
      children: [
        _buildAvailabilityChart(),
        const SizedBox(height: 12),
        _buildTopProblematic(),
      ],
    );
  }
```

---

- [ ] **Step 5: Update build() to use new chart methods**

Replace the `if (_stats != null) ...` block inside `build()` in `_StatsScreenState`. The new block replaces the old text-card content (from Task 1) with the chart widgets. The surrounding `build()` structure stays identical — only this block changes:

```dart
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
```

Also remove `_StatusRow` class at the bottom of the file — it is no longer used. The `_MetricCard` class remains unchanged.

---

- [ ] **Step 6: Add _LegendItem widget class**

Add this class at the bottom of the file, after `_MetricCard`:

```dart
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
```

---

- [ ] **Step 7: Run all tests**

```bash
cd app && flutter test
```

Expected: all 47+ tests pass (no regressions).

---

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/stats_screen.dart app/test/screens/stats_screen_test.dart
git commit -m "feat: add pie chart and horizontal bars to stats screen with responsive layout"
```

---

## Self-Review

**Spec coverage:**
- ✅ Auto-load on entry with 30d default — Task 1 `initState` calls `_loadStats()`
- ✅ Quick chips 7d/30d/90d/Personalizado — Task 1 `_buildPeriodChips()`
- ✅ Selecting chip triggers reload — Task 1 `_selectPeriod()`
- ✅ Location dropdown change triggers reload — Task 1 `onChanged` calls `_loadStats()`
- ✅ PieChart for operative/out_of_service/in_repair — Task 2 `_buildAvailabilityChart()`
- ✅ Horizontal bars for top 5 — Task 2 `_buildTopProblematic()` with `LinearProgressIndicator`
- ✅ Desktop 2-column layout — Task 2 `_buildCharts(isDesktop)` with `Row`
- ✅ Mobile single column — Task 2 `_buildCharts(false)` with `Column`
- ✅ PDF and email buttons preserved — both tasks keep `_generatePdf()` / `_sendByEmail()`
- ✅ fl_chart ^0.69.0 added — Task 1 pubspec

**Placeholder scan:** None found.

**Type consistency:** `_Period` enum defined in Task 1, referenced in Task 2. `_MetricCard` defined in Task 1, used in Task 2 methods. `_stats!` only accessed inside `if (_stats != null)` block — null safety correct.
