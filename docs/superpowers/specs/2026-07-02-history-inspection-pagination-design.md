# Paginación de inspecciones en Histórico — Design

**Fecha:** 2026-07-02

## Objetivo

En la sección "Histórico" (`MachineHistoryDetailBody`), la lista "Historial de inspecciones" muestra todas las inspecciones de la máquina de una sola vez, sin límite. Para máquinas con mucho historial esto hace la lista larga e incómoda de recorrer. Se pagina la lista de a 10 elementos, con controles "Anterior/Siguiente".

## Contexto

Proyecto Cocamatic. `app/lib/widgets/machine_history_detail_body.dart` ya carga TODO el historial vía `api.getInspections(machineId:)` (sin límite, a propósito — es el punto de la sección "Histórico" vs. las últimas 5 que muestra "Máquinas"). El listado "Historial de repuestos" en el mismo widget **no** se pagina — no fue pedido y suele ser una lista corta.

Este es un cambio explícitamente marcado como "No incluido" en el spec original de Histórico (`2026-07-01-machine-history-design.md`): "Paginación del historial". Ahora se pide.

## Decisión: paginación client-side

Se sigue trayendo el historial completo del backend en una sola llamada (sin cambios en `GET /inspections`). La paginación es puramente de presentación: el widget guarda la página actual y solo renderiza el slice correspondiente de la lista ya cargada.

**Por qué esta opción y no paginación real (limit/offset en el backend):** el volumen de inspecciones por máquina en este dominio (revisiones periódicas de máquinas recreativas) es bajo/moderado incluso a varios años vista. Paginación real añadiría cambios de backend, un conteo total, y estado de "página actual" sincronizado con el servidor, sin una ganancia de rendimiento perceptible a esta escala. Decisión confirmada con el usuario.

## Flutter

### `app/lib/widgets/machine_history_detail_body.dart`

`_MachineHistoryDetailBodyState` gana un campo:

```dart
int _inspectionPage = 0;
```

Constante de módulo:

```dart
const _inspectionsPerPage = 10;
```

En el `build()`, tras obtener `inspections` del snapshot, se calcula:

```dart
final totalPages = (inspections.length / _inspectionsPerPage).ceil();
final pageStart = _inspectionPage * _inspectionsPerPage;
final pageItems = inspections.skip(pageStart).take(_inspectionsPerPage).toList();
```

El bloque que hoy hace `...inspections.map((i) => _HistoryInspectionTile(inspection: i))` pasa a iterar `pageItems` en lugar de `inspections`. El contador del título ("Historial de inspecciones (N)") sigue mostrando el total real (`inspections.length`), no el tamaño de la página.

Debajo de la lista de la página actual, si `inspections.length > _inspectionsPerPage`, se agrega una fila de controles:

```
[‹ Anterior]   Página {_inspectionPage + 1} de {totalPages}   [Siguiente ›]
```

- "Anterior" deshabilitado (`onPressed: null`) cuando `_inspectionPage == 0`.
- "Siguiente" deshabilitado cuando `_inspectionPage == totalPages - 1`.
- Cambiar de página hace `setState(() => _inspectionPage++/--)` — no dispara ninguna llamada a red, ya que los datos ya están cargados en memoria.

Si `inspections.length <= _inspectionsPerPage`, no se muestran controles (comportamiento actual, sin cambios visibles).

**Reseteo de página:** no requiere lógica explícita. El widget padre (`MachineHistoryScreen`, tanto en el panel de detalle desktop como al navegar a `/history/:id` en mobile) ya instancia `MachineHistoryDetailBody` con `key: ValueKey(machineId)`/una nueva instancia por máquina — Flutter descarta el `State` anterior (incluida `_inspectionPage`) al cambiar de máquina.

### No incluido

- Paginación de "Historial de repuestos" — no pedido, listas de repuestos suelen ser cortas.
- Paginación real del lado del servidor (`limit`/`offset` en `GET /inspections`).
- Tamaño de página configurable — fijo en 10.
