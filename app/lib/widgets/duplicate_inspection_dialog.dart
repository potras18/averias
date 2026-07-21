import 'package:flutter/material.dart';
import '../models/inspection.dart';
import '../models/machine.dart';

/// Returns the inspection that should be treated as "hoy" for [machine], or
/// `null` if none exists.
///
/// `GET /machines/:id` (see `backend/src/routes/machines.js`) returns
/// `inspections` ordered `ORDER BY inspected_at DESC LIMIT 5`, so the first
/// element is always the most recently created inspection. If that one falls
/// on today's calendar date, it IS today's inspection for this machine.
Inspection? todaysInspection(Machine machine) {
  if (machine.inspections.isEmpty) return null;
  final latest = machine.inspections.first;
  final now = DateTime.now();
  final d = latest.inspectedAt.toLocal();
  final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
  return isToday ? latest : null;
}

/// Checks [machine]'s already-loaded inspection list for a same-day
/// inspection and, if found, shows the appropriate warning dialog instead of
/// letting the caller open the "nueva inspección" create form.
///
/// Returns `true` when the caller should proceed to open the create form (no
/// same-day inspection found). Returns `false` when a dialog was shown and
/// handled the situation: either the technician's own same-day inspection
/// (dialog offers Cancelar/Editar, and Editar invokes [onEditExisting]) or
/// another technician's same-day inspection (dialog offers only Cerrar).
Future<bool> maybeWarnDuplicateInspection({
  required BuildContext context,
  required Machine machine,
  required String? currentUserId,
  required void Function(Inspection existing) onEditExisting,
}) async {
  final existing = todaysInspection(machine);
  if (existing == null) return true;

  if (existing.technicianId != null && existing.technicianId == currentUserId) {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ya registraste una revisión de esta máquina hoy'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: const Text('Editar'),
          ),
        ],
      ),
    );
    if (action == 'edit') onEditExisting(existing);
    return false;
  }

  final name = existing.technicianName ?? 'otro técnico';
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Ya la revisó $name hoy'),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
  return false;
}
