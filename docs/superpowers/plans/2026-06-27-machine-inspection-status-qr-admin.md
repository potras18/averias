# Machine Inspection Status by Day + QR in Admin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show per-machine inspection status (inspected/pending) for a selected day in the machine list, and move QR download buttons to Admin → Machines.

**Architecture:** Backend gains an optional `inspection_date` query param on GET /machines; Flutter model, API client, and cards updated accordingly. QR dialog extracted into admin screen; download code removed from machine list and detail screens.

**Tech Stack:** Node.js/Fastify backend, Flutter/Dart frontend, PostgreSQL, qr_flutter, go_router.

## Global Constraints

- Spanish UI copy throughout (no English user-facing strings)
- No new packages — only existing dependencies
- Backend: no ORM, raw pg queries
- Flutter: sound null safety (Dart 3)

---

### Task 1: Backend — `inspection_date` param on GET /machines

**Files:**
- Modify: `backend/src/routes/machines.js` (GET `/` handler, lines 77–90)

**Interfaces:**
- Produces: `GET /machines?inspection_date=YYYY-MM-DD` → each row includes `inspected: boolean`; absent when param not sent

- [ ] **Step 1: Add `inspection_date` extraction and dynamic EXISTS subquery**

Replace the GET `/` handler in `backend/src/routes/machines.js`:

```js
app.get('/', { preHandler: [app.authenticate] }, async (req) => {
  const { location_id, include_inactive, inspection_date } = req.query
  const where = []
  const params = []
  let i = 1
  if (include_inactive !== 'true') { where.push('m.active = true') }
  if (location_id) { where.push(`m.location_id = $${i++}`); params.push(location_id) }

  let inspectedField = ''
  if (inspection_date) {
    params.push(inspection_date)
    inspectedField = `, EXISTS (
      SELECT 1 FROM inspections
      WHERE machine_id = m.id
        AND inspected_at::date = $${i++}
    ) AS inspected`
  }

  const whereClause = where.length ? `WHERE ${where.join(' AND ')}` : ''
  const { rows } = await app.db.query(
    `SELECT ${MACHINE_FIELDS}${inspectedField}
     FROM machines m
     LEFT JOIN locations l ON l.id = m.location_id
     ${whereClause}
     ORDER BY m.name`,
    params
  )
  return rows
})
```

- [ ] **Step 2: Manual verification**

Restart backend (`docker compose restart` or node process), then:

```bash
# Without param — no inspected field
curl -s -H "Authorization: Bearer <token>" http://localhost:3000/machines | jq '.[0] | keys'
# Expected: does NOT include "inspected"

# With today's date
curl -s -H "Authorization: Bearer <token>" "http://localhost:3000/machines?inspection_date=$(date +%F)" | jq '.[0] | {name, inspected}'
# Expected: { "name": "...", "inspected": true } or false
```

- [ ] **Step 3: Commit**

```bash
git add backend/src/routes/machines.js
git commit -m "feat: add inspection_date param to GET /machines"
```

---

### Task 2: Flutter — Machine model + ApiClient

**Files:**
- Modify: `app/lib/models/machine.dart`
- Modify: `app/lib/services/api_client.dart`

**Interfaces:**
- Produces: `Machine.inspected: bool?` (null = no date filter active)
- Produces: `ApiClient.getMachines({DateTime? inspectionDate})`

- [ ] **Step 1: Add `inspected` field to Machine model**

In `app/lib/models/machine.dart`, add field and constructor param:

```dart
class Machine {
  final String id;
  final String name;
  final String qrCode;
  final String? locationId;
  final String? locationName;
  final bool hasRedemptionTickets;
  final bool active;
  final String? lastStatus;
  final DateTime? lastInspectedAt;
  final List<Inspection> inspections;
  final bool? inspected;  // null = no date filter; true/false = inspected that day

  const Machine({
    required this.id,
    required this.name,
    required this.qrCode,
    this.locationId,
    this.locationName,
    required this.hasRedemptionTickets,
    required this.active,
    this.lastStatus,
    this.lastInspectedAt,
    this.inspections = const [],
    this.inspected,
  });

  factory Machine.fromJson(Map<String, dynamic> json) => Machine(
        id: json['id'] as String,
        name: json['name'] as String,
        qrCode: json['qr_code'] as String,
        locationId: json['location_id'] as String?,
        locationName: json['location_name'] as String?,
        hasRedemptionTickets: json['has_redemption_tickets'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
        lastStatus: json['last_status'] as String?,
        lastInspectedAt: json['last_inspected_at'] != null
            ? DateTime.parse(json['last_inspected_at'] as String)
            : null,
        inspections: (json['inspections'] as List<dynamic>?)
                ?.map((e) => Inspection.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        inspected: json['inspected'] as bool?,
      );
}
```

- [ ] **Step 2: Add `inspectionDate` param to `getMachines()`**

In `app/lib/services/api_client.dart`, replace `getMachines`:

```dart
Future<List<Machine>> getMachines({
  String? locationId,
  bool includeInactive = false,
  DateTime? inspectionDate,
}) async {
  final res = await _dio.get('/machines', queryParameters: {
    if (locationId != null) 'location_id': locationId,
    if (includeInactive) 'include_inactive': 'true',
    if (inspectionDate != null)
      'inspection_date': inspectionDate.toIso8601String().substring(0, 10),
  });
  return (res.data as List).map((j) => Machine.fromJson(j as Map<String, dynamic>)).toList();
}
```

- [ ] **Step 3: Verify no compile errors**

```bash
cd app && flutter analyze lib/models/machine.dart lib/services/api_client.dart
# Expected: No issues found
```

- [ ] **Step 4: Commit**

```bash
git add app/lib/models/machine.dart app/lib/services/api_client.dart
git commit -m "feat: add inspected field to Machine model and inspectionDate param to getMachines"
```

---

### Task 3: MachineCard — inspection status chip

**Files:**
- Modify: `app/lib/widgets/machine_card.dart`

**Interfaces:**
- Consumes: `Machine.inspected: bool?` (from Task 2)
- Produces: `MachineCard` shows green chip "✓ Inspeccionada" or red chip "✗ Pendiente" when `machine.inspected != null`

- [ ] **Step 1: Update MachineCard to show inspection chip**

Replace `app/lib/widgets/machine_card.dart`:

```dart
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
```

- [ ] **Step 2: Verify no compile errors**

```bash
cd app && flutter analyze lib/widgets/machine_card.dart
# Expected: No issues found
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/machine_card.dart
git commit -m "feat: add inspection status chip to MachineCard"
```

---

### Task 4: MachineListScreen — date picker + wire inspection status

**Files:**
- Modify: `app/lib/screens/machine_list_screen.dart`

**Interfaces:**
- Consumes: `ApiClient.getMachines({DateTime? inspectionDate})` (Task 2)
- Consumes: `MachineCard` with `machine.inspected` (Task 3)

- [ ] **Step 1: Add `_inspectionDate` state and update `_loadList`**

In `_MachineListScreenState`, add the field after `bool _isDesktop = false;`:

```dart
DateTime _inspectionDate = DateTime.now();
```

Replace `_loadList()`:

```dart
Future<void> _loadList() async {
  try {
    final machines = await widget.api.getMachines(
      inspectionDate: _inspectionDate,
    );
    if (!mounted) return;
    setState(() {
      _machines = machines;
      _loadingList = false;
      _error = null;
    });
    if (_isDesktop && machines.isNotEmpty) {
      final initialId = widget.preselectedId ?? machines.first.id;
      _selectMachine(initialId);
    }
  } catch (_) {
    if (mounted) setState(() {
      _loadingList = false;
      _error = 'Error al cargar máquinas';
    });
  }
}
```

- [ ] **Step 2: Add `_pickDate()` method**

Add this method to `_MachineListScreenState` (after `_loadRole`):

```dart
Future<void> _pickDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _inspectionDate,
    firstDate: DateTime(2020),
    lastDate: DateTime.now(),
  );
  if (picked != null && mounted) {
    setState(() {
      _inspectionDate = picked;
      _loadingList = true;
    });
    await _loadList();
  }
}
```

- [ ] **Step 3: Add date picker row to `_buildMobile`**

In `_buildMobile`, add the date picker row inside the `Scaffold` body. Replace the body section:

```dart
body: Column(
  children: [
    _buildDatePickerRow(),
    Expanded(
      child: _loadingList
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _loadList, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : _machines.isEmpty
                  ? const Center(child: Text('Sin máquinas registradas'))
                  : RefreshIndicator(
                      onRefresh: _loadList,
                      child: ListView.separated(
                        itemCount: _machines.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => MachineCard(
                          machine: _machines[i],
                          onTap: () => context.push('/machines/${_machines[i].id}'),
                        ),
                      ),
                    ),
    ),
  ],
),
```

- [ ] **Step 4: Add `_buildDatePickerRow()` helper**

Add this method to `_MachineListScreenState`:

```dart
Widget _buildDatePickerRow() {
  final d = _inspectionDate;
  final label =
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      children: [
        const Icon(Icons.calendar_today, size: 18),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _pickDate,
          child: const Text('Cambiar'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 5: Add date picker row to desktop list panel**

In `_buildListPanel()`, add `_buildDatePickerRow()` below the search TextField. Replace the Column children:

```dart
Widget _buildListPanel() {
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            hintText: 'Buscar máquina...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
      _buildDatePickerRow(),
      if (_loadingList)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else
        Expanded(
          child: ListView.separated(
            itemCount: _filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final m = _filtered[i];
              return ListTile(
                selected: m.id == _selectedMachineId,
                title: Text(m.name),
                subtitle: Text(m.locationName ?? ''),
                onTap: () => _selectMachine(m.id),
              );
            },
          ),
        ),
    ],
  );
}
```

- [ ] **Step 6: Remove QR download from desktop detail panel**

In `_buildDetailPanel()`, remove the download button block (the `Center` widget with Row of PNG/PDF buttons, lines ~271–288) and the `_downloadQrPng` and `_downloadQrPdf` methods.

The detail panel section after the QR image should go directly to the divider/inspection button:

```dart
// Remove this entire block from _buildDetailPanel:
// Center(
//   child: Row(
//     mainAxisAlignment: MainAxisAlignment.center,
//     children: [
//       OutlinedButton.icon(icon: ..., label: Text('PNG'), ...),
//       SizedBox(width: 12),
//       OutlinedButton.icon(icon: ..., label: Text('PDF'), ...),
//     ],
//   ),
// ),
```

Also remove unused imports from the top of `machine_list_screen.dart`:
- Remove `import 'dart:ui' as ui;`
- Remove `import 'dart:typed_data';`
- Remove `import '../utils/download_file.dart';`

And remove the two methods `_downloadQrPng` and `_downloadQrPdf` from `_MachineListScreenState`.

- [ ] **Step 7: Verify no compile errors**

```bash
cd app && flutter analyze lib/screens/machine_list_screen.dart
# Expected: No issues found
```

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/machine_list_screen.dart
git commit -m "feat: add date picker and inspection status to machine list; remove QR download"
```

---

### Task 5: MachineDetailScreen — remove QR download buttons

**Files:**
- Modify: `app/lib/screens/machine_detail_screen.dart`

- [ ] **Step 1: Remove PNG/PDF download buttons from mobile view**

In `machine_detail_screen.dart`, remove the download Row (lines ~101–118):

```dart
// Remove this block entirely:
// Center(
//   child: Row(
//     mainAxisAlignment: MainAxisAlignment.center,
//     children: [
//       OutlinedButton.icon(
//         icon: const Icon(Icons.image),
//         label: const Text('PNG'),
//         onPressed: () => _downloadQrPng(machine.qrCode),
//       ),
//       const SizedBox(width: 12),
//       OutlinedButton.icon(
//         icon: const Icon(Icons.picture_as_pdf),
//         label: const Text('PDF'),
//         onPressed: () => _downloadQrPdf(machine),
//       ),
//     ],
//   ),
// ),
```

- [ ] **Step 2: Remove download methods and unused imports**

Remove the `_downloadQrPng` and `_downloadQrPdf` methods from `_MachineDetailScreenState`.

Remove these imports:
```dart
// Remove:
import 'dart:ui' as ui;
import 'dart:typed_data';
import '../utils/download_file.dart';
```

Keep `import 'package:qr_flutter/qr_flutter.dart';` — still used for `QrImageView`.

- [ ] **Step 3: Change StatefulWidget to StatelessWidget** (optional — screen is now effectively stateless except for future loading; skip if it adds complexity)

Skip this step — `_future` and `_redirected` state is still needed.

- [ ] **Step 4: Verify no compile errors**

```bash
cd app && flutter analyze lib/screens/machine_detail_screen.dart
# Expected: No issues found
```

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/machine_detail_screen.dart
git commit -m "feat: remove QR download buttons from machine detail screen"
```

---

### Task 6: AdminScreen — QR dialog in Machines tab

**Files:**
- Modify: `app/lib/screens/admin_screen.dart`

**Interfaces:**
- Consumes: `ApiClient.getMachineQrPdf(String id): Future<Uint8List>` (existing)
- Consumes: `downloadFile(Uint8List, String, String)` from `../utils/download_file.dart`

- [ ] **Step 1: Add imports to admin_screen.dart**

Add at the top of `app/lib/screens/admin_screen.dart`:

```dart
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import '../utils/download_file.dart';
```

- [ ] **Step 2: Add `_showQrDialog` method to `_AdminScreenState`**

Add after `_decommissionMachine`:

```dart
Future<void> _showQrDialog(Machine machine) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(machine.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: machine.qrCode,
            version: QrVersions.auto,
            size: 200,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.image),
                label: const Text('PNG'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _downloadQrPng(machine.qrCode);
                },
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _downloadQrPdf(machine);
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

Future<void> _downloadQrPng(String qrCode) async {
  final painter = QrPainter(
    data: qrCode,
    version: QrVersions.auto,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
  );
  final img = await painter.toImage(512);
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  await downloadFile(byteData!.buffer.asUint8List(), 'qr-$qrCode.png', 'image/png');
}

Future<void> _downloadQrPdf(Machine machine) async {
  final bytes = await widget.api.getMachineQrPdf(machine.id);
  await downloadFile(
    bytes,
    'qr-${machine.name.replaceAll(' ', '-')}.pdf',
    'application/pdf',
  );
}
```

- [ ] **Step 3: Add QR icon button to machines tab**

In `_buildMachinesTab()`, add a QR icon button to each machine's trailing Row, before the edit button:

```dart
trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      icon: const Icon(Icons.qr_code),
      tooltip: 'Ver QR',
      onPressed: () => _showQrDialog(m),
    ),
    IconButton(
      icon: const Icon(Icons.edit),
      tooltip: 'Editar',
      onPressed: () => _showMachineDialog(machine: m),
    ),
    TextButton(
      key: Key('decommission-${m.id}'),
      onPressed: m.active ? () => _decommissionMachine(m) : null,
      child: const Text('Dar de baja'),
    ),
  ],
),
```

- [ ] **Step 4: Verify no compile errors**

```bash
cd app && flutter analyze lib/screens/admin_screen.dart
# Expected: No issues found
```

- [ ] **Step 5: Full analyze**

```bash
cd app && flutter analyze
# Expected: No issues found
```

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/admin_screen.dart
git commit -m "feat: add QR download dialog to admin machines tab"
```

---

## Manual Test Checklist

After all tasks complete, verify end-to-end:

**Inspection status:**
- [ ] Open machine list → date picker shows today's date
- [ ] Machines inspected today show green "✓ Inspeccionada" chip
- [ ] Machines not yet inspected show red "✗ Pendiente" chip
- [ ] Change date to yesterday → chips update accordingly
- [ ] Register an inspection → return to list → machine chip turns green

**QR in Admin:**
- [ ] Go to Admin → Máquinas tab
- [ ] Each machine row has a QR icon button
- [ ] Tapping opens dialog with QR image + PNG/PDF buttons
- [ ] PNG download works
- [ ] PDF download works

**Removed from other screens:**
- [ ] Machine list desktop detail panel: NO PNG/PDF buttons
- [ ] Machine detail screen (mobile): NO PNG/PDF buttons
- [ ] QR image still visible in both (just no download)
