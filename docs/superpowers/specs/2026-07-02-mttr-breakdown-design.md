# MTTR: mediana + top 5 reparaciones más lentas — Design

**Fecha:** 2026-07-02

## Objetivo

Enriquecer la métrica MTTR ya existente en Estadísticas con dos datos adicionales: la mediana de tiempo de reparación (menos sensible a casos extremos que el promedio) y un top 5 de las máquinas con reparación promedio más lenta. Se implementa en una rama aparte, a modo de experimento, para evaluar si aporta valor antes de fusionarla.

## Contexto

Proyecto Cocamatic — gestión de mantenimiento de máquinas recreativas. El MTTR (Mean Time To Repair) ya existe: `backend/src/reports/queries.js:getMttrHours()` calcula el promedio de horas entre que una inspección marca una máquina `out_of_service` y la siguiente inspección de esa máquina la marca `operative`. Se muestra hoy como tarjeta en `app/lib/screens/stats_screen.dart:164-190` y se expone en `GET /stats` como `mttr_hours`.

## Backend

### `backend/src/reports/queries.js`

`getMttrHours(db, filters)` cambia de devolver un `number|null` a devolver `{ mean: number|null, median: number|null }`, reusando la misma CTE `ranked` (par `out_of_service` → `operative` por máquina):

```sql
WITH ranked AS (
  SELECT i.machine_id, i.status, i.inspected_at,
         LEAD(i.status) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_status,
         LEAD(i.inspected_at) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_at
  FROM inspections i
  JOIN machines m ON m.id = i.machine_id
  {where}
)
SELECT
  AVG(EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600) AS mean_hours,
  PERCENTILE_CONT(0.5) WITHIN GROUP (
    ORDER BY EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600
  ) AS median_hours
FROM ranked
WHERE status = 'out_of_service' AND next_status = 'operative'
```

Nueva función `getMttrTopMachines(db, filters)` — mismas transiciones, agrupadas por máquina, top 5 por promedio descendente:

```sql
WITH ranked AS (
  SELECT i.machine_id, m.name, i.status, i.inspected_at,
         LEAD(i.status) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_status,
         LEAD(i.inspected_at) OVER (PARTITION BY i.machine_id ORDER BY i.inspected_at) AS next_at
  FROM inspections i
  JOIN machines m ON m.id = i.machine_id
  {where}
)
SELECT name, AVG(EXTRACT(EPOCH FROM (next_at - inspected_at)) / 3600) AS avg_hours
FROM ranked
WHERE status = 'out_of_service' AND next_status = 'operative'
GROUP BY machine_id, name
ORDER BY avg_hours DESC
LIMIT 5
```

Devuelve `[]` si ninguna máquina tiene una transición completa en el período — mismo caso borde que ya maneja `mttr_hours: null` hoy.

### `backend/src/routes/stats.js`

`buildStatsData()` desestructura `{ mean, median }` de `getMttrHours` y agrega `getMttrTopMachines` al `Promise.all()`. Respuesta de `GET /stats` gana dos campos, el resto queda igual:

```json
{
  "mttr_hours": 4.5,
  "mttr_median_hours": 3.2,
  "mttr_top_machines": [
    { "name": "Mario Kart DX #3", "avg_hours": 12.4 }
  ],
  "...": "resto de campos sin cambios"
}
```

`mttr_hours` conserva su nombre y significado actuales (promedio) — ningún consumidor existente se rompe.

## Flutter

### `app/lib/models/stats.dart`

Nueva clase:

```dart
class MttrTopMachine {
  final String name;
  final double avgHours;

  const MttrTopMachine({required this.name, required this.avgHours});

  factory MttrTopMachine.fromJson(Map<String, dynamic> json) => MttrTopMachine(
    name: json['name'] as String,
    avgHours: (json['avg_hours'] as num).toDouble(),
  );
}
```

`StatsResult` gana dos campos:

```dart
final double? mttrMedianHours;
final List<MttrTopMachine> mttrTopMachines;
```

Parseados en `StatsResult.fromJson` igual que los campos existentes (`mttr_median_hours` nullable num, `mttr_top_machines` lista con default `[]` si el backend no la incluye — no debería pasar, pero evita null-crash si algún test viejo no la mockea).

### `app/lib/screens/stats_screen.dart`

- `_buildSummaryRow()` (línea 164): la tarjeta "MTTR" agrega una segunda línea chica debajo del valor grande: `'Mediana: X.X h'` (o nada si `mttrMedianHours` es null).
- Nueva tarjeta `_buildMttrTopMachines()`, mismo estilo visual que `_buildTopProblematic()` (línea 449: barra horizontal `LinearProgressIndicator` por máquina, nombre truncado a 15 caracteres, valor a la derecha — pero mostrando horas en vez de conteo). Texto vacío: `'Sin datos suficientes'` si la lista viene vacía.
- Se agrega junto a `_buildTopProblematic()` en `_buildCharts()` (línea 497): en desktop, tercer elemento en una fila de 3 (`Availability | Top problemáticas | Top MTTR`) o fila propia debajo — decisión de layout se resuelve durante la implementación, no es un requisito funcional.

## Archivos a crear o modificar

| Archivo | Acción |
|---------|--------|
| `backend/src/reports/queries.js` | `getMttrHours` devuelve `{mean, median}`; nueva `getMttrTopMachines` |
| `backend/src/routes/stats.js` | Usar `{mean, median}`, añadir `mttr_median_hours` y `mttr_top_machines` a la respuesta |
| `backend/test/stats.test.js` | Tests para mediana y top 5 más lentas |
| `app/lib/models/stats.dart` | `MttrTopMachine` + campos nuevos en `StatsResult` |
| `app/lib/screens/stats_screen.dart` | Mediana en tarjeta MTTR + tarjeta nueva top 5 lentas |
| `app/test/screens/stats_screen_test.dart` | Tests de los widgets nuevos |

## No incluido

- PDF (`backend/src/pdf/stats-template.js`) y email de estadísticas — quedan sin la mediana/top-5-lentas por ahora; si el experimento se valida, se agrega en un cambio aparte.
- Desglose de MTTR por técnico.
- Percentiles distintos a la mediana (p90, p95).
- Cambios al nombre o semántica de `mttr_hours` (sigue siendo el promedio).
