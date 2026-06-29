# Report Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Día / Mes / Rango mode selector to ReportScreen so users can pick a single day, a full month, or a free date range before generating a report.

**Architecture:** All changes are in one Flutter file (`report_screen.dart`) and its test. The backend is unchanged — all modes reduce to `from`/`to` strings passed to the existing API. A new `_ReportMode` enum drives which picker widget renders and how `_fromStr`/`_toStr` are computed.

**Tech Stack:** Flutter/Dart, flutter_test, mocktail.

## Global Constraints

- Spanish UI copy: "Día", "Mes", "Rango", "Seleccionar día", "Seleccionar período", Spanish month names (Enero–Diciembre).
- Default mode on first open: `_ReportMode.range` (preserves existing behaviour).
- Día mode: action buttons disabled until a day is selected (`_selectedDay != null`).
- Mes mode: action buttons always enabled; defaults to current month/year.
- Rango mode: action buttons always enabled; null `from`/`to` means "all time" (existing behaviour).
- Last day of month computed as `DateTime(_selectedYear, _selectedMonth + 1, 0).day`.
- `from`/`to` format: `yyyy-MM-dd`.
- Action button keys: `Key('generate-pdf-btn')`, `Key('send-email-btn')`.
- No backend changes.

---

### Task 1: ReportScreen — mode selector + adaptive pickers

**Files:**
- Modify: `app/lib/screens/report_screen.dart`
- Modify: `app/test/screens/report_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.getReportPdf({String? from, String? to, String? locationId})`, `ApiClient.sendReportByEmail(...)` — unchanged signatures.
- Produces: updated `ReportScreen` with `Key('generate-pdf-btn')` and `Key('send-email-btn')` on action buttons.

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `app/test/screens/report_screen_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:averias_app/screens/report_screen.dart';
import 'package:averias_app/services/api_client.dart';
import 'package:averias_app/models/location.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    when(() => api.getLocations()).thenAnswer((_) async => [
      const Location(id: 'loc-1', name: 'Local A'),
    ]);
  });

  testWidgets('shows Generar PDF and Enviar por email buttons', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Generar PDF'), findsOneWidget);
    expect(find.text('Enviar por email'), findsOneWidget);
  });

  testWidgets('shows location dropdown with loaded locations', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Todos los locales'), findsOneWidget);
  });

  testWidgets('tapping Generar PDF in Rango mode calls getReportPdf', (tester) async {
    when(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    verify(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).called(1);
  });

  testWidgets('Rango mode shows Seleccionar período by default', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar período'), findsOneWidget);
  });

  testWidgets('shows mode chips: Día, Mes, Rango', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Día'), findsOneWidget);
    expect(find.text('Mes'), findsOneWidget);
    expect(find.text('Rango'), findsOneWidget);
  });

  testWidgets('tapping Día chip shows Seleccionar día button', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar día'), findsOneWidget);
    expect(find.text('Seleccionar período'), findsNothing);
  });

  testWidgets('tapping Mes chip shows two int dropdowns', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
    expect(find.text('Seleccionar período'), findsNothing);
  });

  testWidgets('tapping Rango chip restores Seleccionar período button', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rango'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar período'), findsOneWidget);
  });

  testWidgets('Día mode: Generar PDF disabled before day selected', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día'));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(
        find.byKey(const Key('generate-pdf-btn')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Mes mode: Generar PDF calls with first and last day of current month',
      (tester) async {
    when(() => api.getReportPdf(
      from: any(named: 'from'),
      to: any(named: 'to'),
      locationId: any(named: 'locationId'),
    )).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    await tester.pumpWidget(MaterialApp(home: ReportScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();

    final now    = DateTime.now();
    final year   = now.year;
    final month  = now.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    final fromStr = '$year-${month.toString().padLeft(2, '0')}-01';
    final toStr   =
        '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

    await tester.tap(find.byKey(const Key('generate-pdf-btn')));
    await tester.pumpAndSettle();

    verify(() => api.getReportPdf(
      from: fromStr,
      to: toStr,
      locationId: any(named: 'locationId'),
    )).called(1);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/report_screen_test.dart 2>&1 | tail -20
```

Expected: failures on new tests (no mode chips, no keys, no Día/Mes pickers).

- [ ] **Step 3: Implement the updated ReportScreen**

Replace the entire contents of `app/lib/screens/report_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../models/location.dart';
import '../utils/download_file.dart';
import '../widgets/desktop_shell_scope.dart';

enum _ReportMode { day, month, range }

class ReportScreen extends StatefulWidget {
  final ApiClient api;
  const ReportScreen({super.key, required this.api});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  _ReportMode _mode = _ReportMode.range;

  DateTime?     _selectedDay;
  int           _selectedMonth = DateTime.now().month;
  int           _selectedYear  = DateTime.now().year;
  DateTimeRange? _dateRange;

  List<Location> _locations = [];
  String?        _selectedLocationId;
  bool           _loading = false;
  String?        _error;

  static const _monthNames = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final locs = await widget.api.getLocations();
      if (mounted) setState(() => _locations = locs);
    } catch (_) {}
  }

  String? get _fromStr {
    switch (_mode) {
      case _ReportMode.day:
        return _selectedDay?.toIso8601String().substring(0, 10);
      case _ReportMode.month:
        return '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-01';
      case _ReportMode.range:
        return _dateRange?.start.toIso8601String().substring(0, 10);
    }
  }

  String? get _toStr {
    switch (_mode) {
      case _ReportMode.day:
        return _selectedDay?.toIso8601String().substring(0, 10);
      case _ReportMode.month:
        final lastDay = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
        return '$_selectedYear-'
            '${_selectedMonth.toString().padLeft(2, '0')}-'
            '${lastDay.toString().padLeft(2, '0')}';
      case _ReportMode.range:
        return _dateRange?.end.toIso8601String().substring(0, 10);
    }
  }

  bool get _hasValidPeriod {
    switch (_mode) {
      case _ReportMode.day:   return _selectedDay != null;
      case _ReportMode.month: return true;
      case _ReportMode.range: return true;
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _selectedDay ?? DateTime.now(),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) setState(() => _selectedDay = picked);
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
      locale: const Locale('es', 'ES'),
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Future<void> _generatePdf() async {
    setState(() { _loading = true; _error = null; });
    try {
      final bytes = await widget.api.getReportPdf(
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      await downloadFile(bytes, 'informe_averias.pdf');
    } on UnsupportedError {
      if (mounted) setState(() => _error = 'Descarga no disponible en esta plataforma');
    } catch (e) {
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

    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.sendReportByEmail(
        emails: emails,
        from: _fromStr,
        to: _toStr,
        locationId: _selectedLocationId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe enviado correctamente')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al enviar el informe');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildPicker() {
    switch (_mode) {
      case _ReportMode.day:
        final label = _selectedDay != null
            ? '${_selectedDay!.day.toString().padLeft(2, '0')}/'
              '${_selectedDay!.month.toString().padLeft(2, '0')}/'
              '${_selectedDay!.year}'
            : 'Seleccionar día';
        return OutlinedButton.icon(
          icon: const Icon(Icons.today),
          label: Text(label),
          onPressed: _pickDay,
        );

      case _ReportMode.month:
        return Row(
          children: [
            DropdownButton<int>(
              value: _selectedMonth,
              items: List.generate(
                12,
                (i) => DropdownMenuItem(
                    value: i + 1, child: Text(_monthNames[i])),
              ),
              onChanged: (v) => setState(() => _selectedMonth = v!),
            ),
            const SizedBox(width: 16),
            DropdownButton<int>(
              value: _selectedYear,
              items: List.generate(
                DateTime.now().year - 2020 + 1,
                (i) => DropdownMenuItem(
                    value: 2020 + i, child: Text('${2020 + i}')),
              ),
              onChanged: (v) => setState(() => _selectedYear = v!),
            ),
          ],
        );

      case _ReportMode.range:
        final dateLabel = _dateRange != null
            ? '${_fromStr} — ${_toStr}'
            : 'Seleccionar período';
        return OutlinedButton.icon(
          icon: const Icon(Icons.date_range),
          label: Text(dateLabel),
          onPressed: _pickDateRange,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    return Scaffold(
      appBar: isDesktop ? null : AppBar(title: const Text('Informes')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Día'),
                  selected: _mode == _ReportMode.day,
                  onSelected: (_) => setState(() => _mode = _ReportMode.day),
                ),
                ChoiceChip(
                  label: const Text('Mes'),
                  selected: _mode == _ReportMode.month,
                  onSelected: (_) =>
                      setState(() => _mode = _ReportMode.month),
                ),
                ChoiceChip(
                  label: const Text('Rango'),
                  selected: _mode == _ReportMode.range,
                  onSelected: (_) =>
                      setState(() => _mode = _ReportMode.range),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPicker(),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedLocationId,
              decoration:
                  const InputDecoration(labelText: 'Local (opcional)'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Todos los locales')),
                ..._locations.map(
                  (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
                ),
              ],
              onChanged: (v) => setState(() => _selectedLocationId = v),
            ),
            const SizedBox(height: 28),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.icon(
                    key: const Key('generate-pdf-btn'),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Generar PDF'),
                    onPressed: _hasValidPeriod ? _generatePdf : null,
                  ),
                  OutlinedButton.icon(
                    key: const Key('send-email-btn'),
                    icon: const Icon(Icons.email),
                    label: const Text('Enviar por email'),
                    onPressed: _hasValidPeriod ? _sendByEmail : null,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/mauri/Devs/averias/app
flutter test test/screens/report_screen_test.dart 2>&1 | tail -20
```

Expected: all 9 tests pass.

- [ ] **Step 5: Run flutter analyze**

```bash
cd /Users/mauri/Devs/averias/app
flutter analyze lib/screens/report_screen.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 6: Run full Flutter test suite**

```bash
cd /Users/mauri/Devs/averias/app
flutter test 2>&1 | tail -10
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/mauri/Devs/averias
git add app/lib/screens/report_screen.dart app/test/screens/report_screen_test.dart
git commit -m "feat: add Día/Mes/Rango mode selector to ReportScreen"
```
