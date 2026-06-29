# Gráficas SVG en PDF de Estadísticas

**Fecha:** 2026-06-30

## Objetivo

Incluir las dos gráficas de la pantalla de estadísticas (tarta de disponibilidad y barras de tendencia diaria) en los PDFs generados por `/stats/pdf` y enviados por `/stats/email`.

## Contexto

El PDF se genera en el backend con Puppeteer renderizando HTML. La función `buildStatsHtml()` en `backend/src/pdf/stats-template.js` produce el HTML. Actualmente sólo contiene texto y tablas — sin gráficas. Los datos necesarios ya existen: `buildStatsData()` calcula `dailyBreakdown` pero no lo pasa a `buildStatsHtml()`.

## Arquitectura

Cambios exclusivamente en backend. Sin modificaciones en Flutter ni en dependencias.

### `backend/src/pdf/stats-template.js`

Añadir dos funciones internas:

**`buildPieChartSvg({ operative, outOfService, inRepair })`**
- SVG 300×200 px con círculo de sectores y leyenda a la derecha
- Tres sectores proporcionales a los porcentajes
- Colores: operative → `#43a047`, out_of_service → `#e53935`, in_repair → `#fb8c00`
- Si los tres porcentajes son 0, devuelve `<p><em>Sin datos</em></p>`
- Aritmética: convertir cada porcentaje a ángulo (radianes), calcular coordenadas del arco con `Math.cos`/`Math.sin`, generar `<path>` con el comando `A` (arc)

**`buildBarChartSvg(dailyBreakdown)`**
- SVG 520×180 px con barras apiladas por día
- Si `dailyBreakdown` está vacío o tiene un único día, devuelve `<p><em>Sin datos de tendencia</em></p>`
- Eje X: fechas formateadas `dd/mm`, rotadas 45° si hay más de 7 días
- Eje Y: implícito (altura proporcional al máximo del período)
- Cada barra: tres rectángulos apilados (operative encima, luego out_of_service, luego in_repair) — mismo orden visual que Flutter
- Ancho de barra: proporcional al espacio disponible, máximo 28px, mínimo 6px
- Si un día tiene total 0, se muestra barra vacía (sólo el eje)

**`buildStatsHtml({ ..., dailyBreakdown })`**
- Añade el parámetro `dailyBreakdown` (array)
- Sustituye la sección "Disponibilidad" (actualmente tabla de texto) por: tarta SVG arriba + tabla de porcentajes debajo
- Añade nueva sección "Tendencia diaria" entre "Disponibilidad" y "Top 5 máquinas"

**Estructura del PDF resultante:**
1. Cabecera (período, local, técnico, fecha de generación)
2. MTTR
3. Disponibilidad — tarta SVG + tabla de porcentajes
4. Tendencia diaria — bar chart SVG
5. Top 5 máquinas problemáticas — tabla (ya existe)

### `backend/src/routes/stats.js`

En ambos handlers (`GET /pdf` y `POST /email`), añadir `dailyBreakdown: data.dailyBreakdown` en la llamada a `buildStatsHtml()`.

## Colores

Idénticos a la pantalla Flutter:

| Estado | Color |
|--------|-------|
| Operativa | `#43a047` (verde) |
| Fuera de servicio | `#e53935` (rojo) |
| En reparación | `#fb8c00` (naranja) |

## Archivos a modificar

| Archivo | Cambio |
|---------|--------|
| `backend/src/pdf/stats-template.js` | Añadir `buildPieChartSvg`, `buildBarChartSvg`; actualizar `buildStatsHtml` |
| `backend/src/routes/stats.js` | Pasar `dailyBreakdown` a `buildStatsHtml` en `/pdf` y `/email` |

## No incluido

- Gráficas de lector de tarjetas ni dispensador (no son gráficas en la pantalla Flutter)
- Cambios en Flutter
- Dependencias nuevas
- Informe de averías (`/reports/pdf`) — tiene su propia template, fuera de scope
