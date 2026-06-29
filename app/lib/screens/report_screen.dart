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
            ? '$_fromStr — $_toStr'
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
