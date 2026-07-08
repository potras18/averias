import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String? status;
  const StatusBadge({super.key, this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'out_of_service' => ('Fuera de servicio', Colors.red),
      'in_repair' => ('En reparación', Colors.orange),
      _ => ('Operativa', Colors.green),
    };
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
