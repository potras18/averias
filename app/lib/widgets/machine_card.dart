import 'package:flutter/material.dart';
import '../models/machine.dart';
import 'status_badge.dart';

class MachineCard extends StatelessWidget {
  final Machine machine;
  final VoidCallback onTap;
  const MachineCard({super.key, required this.machine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(machine.name),
      subtitle: machine.locationName != null ? Text(machine.locationName!) : null,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusBadge(status: machine.lastStatus),
          if (machine.inspected != null) ...[
            const SizedBox(height: 4),
            _InspectionChip(inspected: machine.inspected!),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

class _InspectionChip extends StatelessWidget {
  final bool inspected;
  const _InspectionChip({required this.inspected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: inspected ? Colors.green[100] : Colors.red[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        inspected ? '✓ Inspeccionada' : '✗ Pendiente',
        style: TextStyle(
          fontSize: 11,
          color: inspected ? Colors.green[800] : Colors.red[800],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
