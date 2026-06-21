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
      trailing: StatusBadge(status: machine.lastStatus),
      onTap: onTap,
    );
  }
}
