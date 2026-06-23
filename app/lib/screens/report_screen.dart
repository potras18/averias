import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../models/location.dart';
import '../utils/download_file.dart';
import '../widgets/desktop_shell_scope.dart';

class ReportScreen extends StatefulWidget {
  final ApiClient api;
  const ReportScreen({super.key, required this.api});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTimeRange? _dateRange;
  String? _selectedLocationId;
  List<Location> _locations = [];
  bool _loading = false;
  String? _error;

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

  String? get _fromStr => _dateRange != null
      ? _dateRange!.start.toIso8601String().substring(0, 10)
      : null;

  String? get _toStr => _dateRange != null
      ? _dateRange!.end.toIso8601String().substring(0, 10)
      : null;

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

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dateRange != null
        ? '${_fromStr} — ${_toStr}'
        : 'Seleccionar período';

    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    return Scaffold(
      appBar: isDesktop ? null : AppBar(title: const Text('Informes')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(dateLabel),
              onPressed: _pickDateRange,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedLocationId,
              decoration: const InputDecoration(labelText: 'Local (opcional)'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Todos los locales'),
                ),
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
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Generar PDF'),
                    onPressed: _generatePdf,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.email),
                    label: const Text('Enviar por email'),
                    onPressed: _sendByEmail,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
