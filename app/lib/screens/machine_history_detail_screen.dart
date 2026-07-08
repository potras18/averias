import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/desktop_shell_scope.dart';
import '../widgets/machine_history_detail_body.dart';

class MachineHistoryDetailScreen extends StatefulWidget {
  final ApiClient api;
  final StorageService storage;
  final String machineId;

  const MachineHistoryDetailScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.machineId,
  });

  @override
  State<MachineHistoryDetailScreen> createState() => _MachineHistoryDetailScreenState();
}

class _MachineHistoryDetailScreenState extends State<MachineHistoryDetailScreen> {
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = DesktopShellScope.of(context)?.isDesktop ?? false;
    if (isDesktop) {
      if (!_redirected) {
        _redirected = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/history?selected=${widget.machineId}');
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: MachineHistoryDetailBody(api: widget.api, storage: widget.storage, machineId: widget.machineId),
    );
  }
}
