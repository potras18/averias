import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/machine.dart';
import '../models/location.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/desktop_shell_scope.dart';
import '../widgets/machine_history_detail_body.dart';

class MachineHistoryScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final String? preselectedId;

  const MachineHistoryScreen({
    super.key,
    required this.api,
    required this.storage,
    this.preselectedId,
  });

  @override
  State<MachineHistoryScreen> createState() => _MachineHistoryScreenState();
}

class _MachineHistoryScreenState extends State<MachineHistoryScreen> {
  List<Machine> _machines = [];
  List<Location> _locations = [];
  bool _loadingList = true;
  String? _error;
  String? _selectedLocationId;
  String? _selectedMachineId;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isDesktop = false;

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _loadMachines();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    final locations = await widget.api.getLocations();
    if (mounted) setState(() => _locations = locations);
  }

  Future<void> _loadMachines() async {
    setState(() => _loadingList = true);
    try {
      final machines = await widget.api.getMachines(
        locationId: _selectedLocationId,
        includeInactive: true,
      );
      if (!mounted) return;
      setState(() {
        _machines = machines;
        _loadingList = false;
        _error = null;
      });
      if (_isDesktop && _selectedMachineId == null && widget.preselectedId != null) {
        setState(() => _selectedMachineId = widget.preselectedId);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingList = false;
          _error = 'Error al cargar máquinas';
        });
      }
    }
  }

  List<Machine> get _filtered {
    if (_searchQuery.isEmpty) return _machines;
    final q = _searchQuery.toLowerCase();
    return _machines.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return _isDesktop ? _buildDesktop(context) : _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildList((id) => context.push('/history/$id'))),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final filtered = _filtered;
    final selectedVisible = _selectedMachineId != null &&
        filtered.any((m) => m.id == _selectedMachineId);
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: Column(
              children: [
                _buildFilters(),
                Expanded(child: _buildList((id) => setState(() => _selectedMachineId = id))),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: selectedVisible
                ? MachineHistoryDetailBody(
                    key: ValueKey(_selectedMachineId),
                    api: widget.api,
                    storage: widget.storage,
                    machineId: _selectedMachineId!,
                  )
                : const Center(child: Text('Selecciona una máquina')),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Buscar máquina...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: _selectedLocationId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Ubicación',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todas las ubicaciones')),
              ..._locations.map((l) => DropdownMenuItem<String?>(value: l.id, child: Text(l.name))),
            ],
            onChanged: (value) {
              setState(() => _selectedLocationId = value);
              _loadMachines();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildList(void Function(String id) onSelect) {
    if (_loadingList) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _loadMachines, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return const Center(child: Text('Sin máquinas encontradas'));
    }
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = filtered[i];
        return ListTile(
          selected: m.id == _selectedMachineId,
          title: Text(m.name),
          subtitle: Text(m.locationName ?? ''),
          onTap: () => onSelect(m.id),
        );
      },
    );
  }
}
