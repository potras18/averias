# Informes/Estadísticas: la revisión más reciente del día prevalece

## Contexto

Si una máquina se revisa más de una vez el mismo día, hoy Informes y
Estadísticas cuentan **todas** las revisiones de ese día como registros
independientes: el listado del PDF muestra cada una por separado, y los
porcentajes operativa/fuera de servicio/reparación, el ranking de máquinas
problemáticas, el desglose diario, y las estadísticas de lector de
tarjetas/dispensador de tickets las cuentan todas. Una máquina revisada 3
veces el mismo día pesa 3x en esos cálculos frente a una revisada 1 vez.

Se cambia la regla: **por máquina y por día, solo cuenta la revisión más
reciente** — en el listado y en todos los cálculos derivados.

## Decisión de alcance

- Aplica a **Informes y Estadísticas por igual** (comparten la misma query
  base `getInspectionRows` y el mismo `buildSummary`; bifurcar la lógica
  crearía dos fuentes de verdad).
- Aplica a **todas** las métricas basadas en revisiones que hoy cuentan cada
  fila sin deduplicar: listado del PDF (`groupByLocation`), % operativa/OOS/
  reparación (`buildSummary`), ranking de máquinas problemáticas
  (`getTopProblematic`), desglose diario de Estadísticas (`getDailyBreakdown`),
  % lector de tarjetas (`getCardReaderStats`), % dispensador de tickets
  (`getDispenserStats`). Consistencia total dentro del mismo informe/PDF.
- **No aplica** a: `getMttrHours`/`getMttrTopMachines` (miden tiempo entre
  transiciones reales de estado; una revisión duplicada el mismo día no
  cambia ninguna transición real), `getMachineStates` (ya devuelve una fila
  por máquina, la más reciente en todo el rango — no es un concepto "por
  día"), `getIncidenciaResolution` (otra entidad, no inspecciones).

## Backend

### `dedupeLatestPerMachineDay(rows)` (nueva, en `backend/src/reports/queries.js`)

Recibe el array que ya devuelve `getInspectionRows` (viene ordenado
`ORDER BY l.name NULLS LAST, m.name, i.inspected_at DESC` — para una misma
máquina, sus filas son contiguas y la más reciente aparece primero). Se
queda con la primera fila vista por cada `(machine_id, fecha)`:

```js
function dedupeLatestPerMachineDay(rows) {
  const seen = new Set()
  const result = []
  for (const row of rows) {
    const day = new Date(row.inspected_at).toISOString().slice(0, 10)
    const key = `${row.machine_id}_${day}`
    if (seen.has(key)) continue
    seen.add(key)
    result.push(row)
  }
  return result
}
```

### `getTopProblematic`, `getDailyBreakdown`, `getCardReaderStats`, `getDispenserStats`: de query SQL a función JS

`getInspectionRows` ya trae todos los campos que estas cuatro funciones
necesitan (`status`, `machine_id`, `machine_name`, `inspected_at`,
`card_reader_ok`, `card_reader_failure_type`, `dispenser_ok`,
`ticket_level`). En vez de mantener 4 queries SQL independientes con la
misma lógica de dedup duplicada en cada una (riesgo de que diverjan), las
cuatro pasan a ser funciones **síncronas** que reciben el array ya
deduplicado — mismo dato de entrada para toda métrica, mismo resultado
garantizado.

Firma nueva: `getTopProblematic(rows)`, `getDailyBreakdown(rows)`,
`getCardReaderStats(rows)`, `getDispenserStats(rows)` — ya no reciben
`(db, filters)`, el filtrado por fecha/local ya ocurrió en la query de
`getInspectionRows`.

### `buildSummary(rows)` y `groupByLocation(rows)`

Sin cambio de firma — simplemente se les pasa el array deduplicado en vez
del array crudo.

### `reports.js` y `stats.js`

Ambos llaman `getInspectionRows` una vez, deduplican con
`dedupeLatestPerMachineDay`, y pasan ese único array a `buildSummary`,
`groupByLocation` (solo Informes), `getTopProblematic`,
`getDailyBreakdown`/`getCardReaderStats`/`getDispenserStats` (solo
Estadísticas). Efecto colateral positivo: menos queries a la BD (esas 4
pasan de SQL a cálculo en memoria sobre datos ya traídos).

### Tests

En `backend/test/stats.test.js` y `backend/test/reports.test.js`: seed de
una máquina con 2 inspecciones el mismo día con distinto estado (p.ej.
`out_of_service` por la mañana, `operative` por la tarde) → verificar que
solo la de la tarde cuenta en `pct_operative`/`pct_out_of_service`,
`top_problematic`, `daily_breakdown` (esa fecha solo suma 1 al contador de
`operative`, no 1+1 en dos contadores), `card_reader_stats`,
`dispenser_stats`, y en el listado del PDF de Informes
(`groupByLocation`/`buildReportHtml`, vía el mock de `buildReportHtml` ya
usado en `reports.test.js`).

## Fuera de alcance

- No se cambia qué revisión "prevalece" más allá de listados/cálculos
  agregados — la revisión descartada sigue existiendo en BD (esto no borra
  nada, solo afecta qué se cuenta/muestra en Informes y Estadísticas).
- No se toca `GET /inspections` (listado crudo usado por Histórico/Detalle
  de máquina) ni `machines.js` (`last_status`) — siguen mostrando cada
  revisión individual, sin deduplicar, como corresponde a un histórico.
