# Stats Screen — Extended Charts & Metrics Design

**Date:** 2026-06-28

## Goal

Ampliar la pantalla de Estadísticas con: gráfico de tendencia de inspecciones por día (desglosado por estado), card de lector de tarjeta (% OK / % Fallo / tipo fallo más frecuente) y card de dispensador de tickets (% OK / distribución de niveles). Cambiar chips de período a 7d / 15d / 30d / Personalizado (eliminar 90d, default sigue siendo 30d).

---

## Approach

Extender `GET /stats` con 3 nuevos campos en el response. Una sola llamada API, sin nuevo endpoint. Todos los datos ya existen en `inspections` + `ticket_checks` — sin migración de DB.

---

## Backend

### Nuevas funciones en `backend/src/reports/queries.js`

**`getDailyBreakdown(db, { from, to, locationId })`**

Agrupa inspecciones por fecha, cuenta por estado:

```js
SELECT
  inspected_at::date AS date,
  COUNT(*) FILTER (WHERE i.status = 'operative')     AS operative,
  COUNT(*) FILTER (WHERE i.status = 'out_of_service') AS out_of_service,
  COUNT(*) FILTER (WHERE i.status = 'in_repair')      AS in_repair
FROM inspections i
JOIN machines m ON m.id = i.machine_id
[WHERE filters]
GROUP BY inspected_at::date
ORDER BY date ASC
```

Returns: `[{ date: "YYYY-MM-DD", operative: N, out_of_service: N, in_repair: N }]`

**`getCardReaderStats(db, { from, to, locationId })`**

```js
SELECT
  COUNT(*) FILTER (WHERE card_reader_ok = true)  AS ok_count,
  COUNT(*) FILTER (WHERE card_reader_ok = false) AS fail_count,
  COUNT(*)                                        AS total
FROM inspections i
JOIN machines m ON m.id = i.machine_id
[WHERE filters]
```

Para `top_failure_type`, segunda query:
```js
SELECT card_reader_failure_type, COUNT(*) AS n
FROM inspections i
JOIN machines m ON m.id = i.machine_id
WHERE card_reader_ok = false [AND filters]
GROUP BY card_reader_failure_type
ORDER BY n DESC
LIMIT 1
```

Returns:
```js
{
  pct_ok: 82.5,
  pct_fail: 17.5,
  top_failure_type: "no_reconoce_tarjeta"  // null si no hay fallos
}
```

**`getDispenserStats(db, { from, to, locationId })`**

Inspecciones que tienen `ticket_check` registrado:

```js
SELECT
  COUNT(*) AS checked,
  COUNT(*) FILTER (WHERE tc.dispenser_ok = true)         AS ok_count,
  COUNT(*) FILTER (WHERE tc.ticket_level = 'low')        AS low_count,
  COUNT(*) FILTER (WHERE tc.ticket_level = 'medium')     AS medium_count,
  COUNT(*) FILTER (WHERE tc.ticket_level = 'high')       AS high_count
FROM inspections i
JOIN machines m ON m.id = i.machine_id
LEFT JOIN ticket_checks tc ON tc.inspection_id = i.id
[WHERE filters]
```

Porcentaje `pct_no_check` = inspecciones sin `ticket_check` / total inspecciones.

Returns:
```js
{
  pct_ok: 90.0,
  pct_no_check: 10.0,
  pct_low: 5.0,
  pct_medium: 60.0,
  pct_high: 25.0
}
```

### Cambios en `backend/src/routes/stats.js`

`buildStatsData` llama las 3 nuevas funciones en el `Promise.all` existente:

```js
const [rows, mttrHours, topProblematic, dailyBreakdown, cardReaderStats, dispenserStats] =
  await Promise.all([
    getInspectionRows(db, filters),
    getMttrHours(db, filters),
    getTopProblematic(db, filters),
    getDailyBreakdown(db, filters),
    getCardReaderStats(db, filters),
    getDispenserStats(db, filters),
  ])
```

GET `/` response añade:
```js
{
  // ... campos existentes ...
  daily_breakdown:  dailyBreakdown,
  card_reader_stats: cardReaderStats,
  dispenser_stats:   dispenserStats,
}
```

---

## Flutter — Modelos (`app/lib/models/stats.dart`)

Nuevas clases:

```dart
class DailyBreakdown {
  final DateTime date;
  final int operative;
  final int outOfService;
  final int inRepair;

  const DailyBreakdown({
    required this.date,
    required this.operative,
    required this.outOfService,
    required this.inRepair,
  });

  factory DailyBreakdown.fromJson(Map<String, dynamic> json) => DailyBreakdown(
    date: DateTime.parse(json['date'] as String),
    operative: json['operative'] as int,
    outOfService: json['out_of_service'] as int,
    inRepair: json['in_repair'] as int,
  );
}

class CardReaderStats {
  final double pctOk;
  final double pctFail;
  final String? topFailureType;

  const CardReaderStats({
    required this.pctOk,
    required this.pctFail,
    this.topFailureType,
  });

  factory CardReaderStats.fromJson(Map<String, dynamic> json) => CardReaderStats(
    pctOk: (json['pct_ok'] as num).toDouble(),
    pctFail: (json['pct_fail'] as num).toDouble(),
    topFailureType: json['top_failure_type'] as String?,
  );
}

class DispenserStats {
  final double pctOk;
  final double pctNoCheck;
  final double pctLow;
  final double pctMedium;
  final double pctHigh;

  const DispenserStats({
    required this.pctOk,
    required this.pctNoCheck,
    required this.pctLow,
    required this.pctMedium,
    required this.pctHigh,
  });

  factory DispenserStats.fromJson(Map<String, dynamic> json) => DispenserStats(
    pctOk: (json['pct_ok'] as num).toDouble(),
    pctNoCheck: (json['pct_no_check'] as num).toDouble(),
    pctLow: (json['pct_low'] as num).toDouble(),
    pctMedium: (json['pct_medium'] as num).toDouble(),
    pctHigh: (json['pct_high'] as num).toDouble(),
  );
}
```

`StatsResult` se extiende con 3 campos nuevos (required, nunca null — el backend siempre los devuelve):

```dart
final List<DailyBreakdown> dailyBreakdown;
final CardReaderStats cardReaderStats;
final DispenserStats dispenserStats;
```

---

## Flutter — UI (`app/lib/screens/stats_screen.dart`)

### Chips de período

```dart
enum _Period { d7, d15, d30, custom }
```

Labels: `'7d'` / `'15d'` / `'30d'` / `'Personalizado'`. Durations: 7 / 15 / 30 días. Default: `_Period.d30`.

### Layout vertical (scroll)

1. Chips 7d / 15d / 30d / Personalizado
2. Dropdown local
3. Row: Card MTTR + Card Total máquinas *(sin cambios)*
4. **[NUEVO]** Card tendencia — stacked BarChart
5. **[NUEVO]** Row (desktop) / Column (mobile): Card lector + Card dispensador
6. Row (desktop) / Column (mobile): PieChart disponibilidad + Top 5 *(sin cambios)*
7. Botones PDF / Email

### Gráfico tendencia (`_buildTrendChart`)

Usa `BarChart` de fl_chart con `BarChartRodStackItem`:
- Verde (`Colors.green[600]`): operative
- Rojo (`Colors.red[600]`): out_of_service
- Naranja (`Colors.orange[600]`): in_repair
- Altura fija: 180px
- Eje X: etiquetas `dd/MM` — se muestran todas para 7/15 días; cada 5 días para 30 días
- Si `dailyBreakdown.isEmpty`: `Center(child: Text('Sin datos en el período'))`
- Contenedor con `SingleChildScrollView(scrollDirection: Axis.horizontal)` para períodos largos

### Card lector de tarjeta (`_buildCardReaderCard`)

```
Título: "Lector de tarjeta"
LinearProgressIndicator:
  value: pctOk / 100
  color: verde, backgroundColor: rojo[100]
Texto: "✓ OK: 82.5%  ✗ Fallo: 17.5%"
Si topFailureType != null:
  Text("Fallo más frecuente: <tipo>", style: gris pequeño)
```

### Card dispensador (`_buildDispenserCard`)

```
Título: "Dispensador de tickets"
LinearProgressIndicator:
  value: pctOk / 100
  color: verde
Texto: "✓ OK: 90.0%"
Si pctNoCheck > 0: Text("Sin registro: 10.0%", style: gris pequeño)
Row de chips de nivel:
  Chip "Bajo: 5.0%"  (Colors.red[100])
  Chip "Medio: 60.0%" (Colors.orange[100])
  Chip "Alto: 25.0%"  (Colors.green[100])
  — solo chips con valor > 0
```

---

## Testing

### Backend (`backend/test/stats.test.js`)

- `getDailyBreakdown` agrupa por fecha y cuenta status correctamente
- `getCardReaderStats` calcula pct_ok / pct_fail / top_failure_type
- `getDispenserStats` calcula distribución de ticket levels + pct_no_check
- `GET /stats` response incluye `daily_breakdown`, `card_reader_stats`, `dispenser_stats`

### Flutter (`app/test/screens/stats_screen_test.dart`)

- Chip `'15d'` existe; chip `'90d'` no existe
- Gráfico tendencia visible cuando `dailyBreakdown` tiene datos
- Mensaje "Sin datos en el período" cuando `dailyBreakdown` vacío
- Card lector visible con textos de % y tipo de fallo
- Card dispensador visible con chips de nivel

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `backend/src/reports/queries.js` | +3 funciones: getDailyBreakdown, getCardReaderStats, getDispenserStats |
| `backend/src/routes/stats.js` | Promise.all con 6 funciones; 3 nuevos campos en response |
| `backend/test/stats.test.js` | Tests para nuevas funciones y response |
| `app/lib/models/stats.dart` | +3 clases; StatsResult extendido |
| `app/lib/screens/stats_screen.dart` | Chips 7/15/30/custom; 3 nuevos widgets |
| `app/test/screens/stats_screen_test.dart` | Tests para nuevos widgets y chip 15d |

---

## Fuera de alcance

- No se añade paginación ni exportación del gráfico de tendencia
- No se añade agrupación semanal para períodos largos (siempre por día)
- El PDF existente no incluye los nuevos gráficos (solo los datos textuales actuales)
