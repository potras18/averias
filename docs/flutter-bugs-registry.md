# Flutter Bugs Registry — averias

Registro de bugs encontrados y corregidos en este proyecto. Objetivo: no repetirlos.

---

## BUG-001: Desktop layout sin Material ancestor

**Síntoma:** `No material widget found` al cargar el dashboard en desktop.

**Causa:** `MachineListScreen._buildDesktop()` retornaba un `Row` desnudo sin `Scaffold`. `ListTile`, `OutlinedButton`, `FilledButton`, etc. requieren un `Material` ancestor. El camino mobile usa `Scaffold` como root; el desktop no lo hacía.

**Fix:** Envolver el `Row` en `Scaffold(body: Row(...))`.

**Regla:** Todo widget que retorne una pantalla completa en desktop debe retornar `Scaffold`, igual que en mobile. Nunca retornar un `Row`/`Column` desnudo como root de una pantalla.

---

## BUG-002: InheritedWidget con dependents registrados — `_dependents.isEmpty`

**Síntoma:** `Assertion failed: framework.dart:6268 _dependents.isEmpty is not true`

**Causa raíz (investigación):** Este error era una **cascada secundaria** del BUG-003. El error primario era el `TextEditingController` disposed prematuramente (ver BUG-003). Al crashear `TextFormField` durante un rebuild, el árbol de widgets quedaba en estado inconsistente dejando dependents InheritedWidget sin limpiar.

**Fixes aplicados en el camino (no eran la causa raíz):**

1. `DesktopShellScope.of()`: cambio de `dependOnInheritedWidgetOfExactType` → `getInheritedWidgetOfExactType`. Correcto por otras razones: `LayoutBuilder` ya maneja el rebuild completo cuando cambia `isDesktop`, la suscripción reactiva no agrega valor y podía causar el assertion si `DesktopShellScope` se desmontaba.

2. `AdminScreen`: reemplazar `DefaultTabController` en `build()` por `TabController` manual en `initState()`/`dispose()`. Correcto por diseño: `DefaultTabController` crea `_TabControllerScope` (InheritedWidget) dentro de `build()`. Si el widget raíz cambia de tipo entre renders (e.g., `_loading` condicional alterna entre `Scaffold` y `DefaultTabController`), el `_TabControllerScope` puede desmontarse con dependents vivos.

**Regla:** Si un `StatefulWidget` con InheritedWidget (como `DefaultTabController`) aparece condicionalmente en `build()` como root widget (cambia de tipo según estado), moverlo a `initState()`/`dispose()` para garantizar estabilidad del árbol.

---

## BUG-003 (ROOT CAUSE de BUG-002): TextEditingController disposed antes de que el dialog termine su animación

**Síntoma primario:** `A TextEditingController was used after being disposed.`

**Síntoma secundario en cascada:** `_dependents.isEmpty is not true` (BUG-002).

**Stack trace relevante:**
```
package:flutter/src/widgets/transitions.dart didUpdateWidget
package:flutter/src/widgets/framework.dart update
```

**Causa:** En `_showMachineDialog()` y `_showLocationDialog()`, `nameCtrl.dispose()` se llamaba inmediatamente después de que `showDialog<bool>()` resolvía:

```dart
final confirmed = await showDialog<bool>(...);

if (confirmed != true) {
  nameCtrl.dispose();  // ← BUG: dialog todavía animando salida
  return;
}
final name = nameCtrl.text.trim();
nameCtrl.dispose();  // ← BUG: dialog todavía animando salida
await widget.api.createMachineAdmin(...);
```

`showDialog` resuelve cuando `Navigator.pop()` dispara, NO cuando la animación de salida termina (~200ms). Durante esa animación, `TextFormField` sigue montado y llama `nameCtrl.addListener()` → controller ya disposed → crash.

**Fix:**
```dart
// Extraer texto antes de cualquier retorno
final name = nameCtrl.text.trim();

// Cancel: retornar sin dispose — nameCtrl es variable local,
// TextFormField remueve su listener al desmontarse, GC lo limpia
if (confirmed != true) return;

// Confirmed: hacer trabajo async primero (tarda >> 200ms → animación ya terminó)
await widget.api.createMachineAdmin(...);
await _load();
nameCtrl.dispose();  // ← seguro: animación completada hace tiempo
```

**Regla:** Nunca llamar `controller.dispose()` inmediatamente después de `await showDialog()`. La animación de salida del dialog (~200ms) mantiene el widget tree montado. Siempre disponer DESPUÉS del trabajo async (que tarda más que la animación), o dejar que el GC limpie controllers de corta vida.

---

## BUG-004: `mobile_scanner` crashea la cámara SOLO en build release de Android (funciona en debug)

**Síntoma:** En APK release, la pantalla de escaneo QR muestra fondo negro con icono de exclamación. En debug funciona perfecto. Con permiso de cámara concedido, el error real (una vez instrumentado) es `genericError`, code "error", mensaje una excepción Java nativa tipo `attempt to invoke virtual method '...getClass()' on a null object reference`.

**Investigación (3 intentos, todos en `mobile_scanner`):**
1. Sin `errorBuilder` custom, el widget no mostraba ningún detalle — solo un icono genérico del paquete. Se añadió `errorBuilder` mostrando `error.errorCode` + `error.errorDetails?.message/code` → confirmó `genericError` con un NPE nativo.
2. Se subió `mobile_scanner` 5.2.3→7.2.0 (coincide con un issue abierto y sin resolver en el repo del paquete: "Android release build camera doesn't start at all"). El crash cambió de sitio pero seguía siendo el mismo patrón: NPE en una clase ya minificada de un vendor (`o5.b.a(k5.b)`).
3. Se cambió de variante **bundled** → **unbundled** MLKit (`dev.steenbakker.mobile_scanner.useUnbundled=true`). El crash **persistió con el mismo patrón exacto**, solo cambiaron las letras de la clase minificada (`m5.c m5.b.a(j5.b)`).

**Causa raíz:** El bug vive en la capa compartida CameraX/MLKit que usan TANTO la variante bundled como unbundled de `mobile_scanner` — no es un problema de configuración de nuestro lado, ni algo arreglable cambiando parámetros del paquete.

**Fix:** Reemplazar `mobile_scanner` por `flutter_zxing`, que usa el plugin oficial `camera` de Flutter (la misma vía de acceso a cámara que ya usa `image_picker` en esta app, que sí funciona en release) para la vista previa, y una librería C++ separada (zxing-cpp vía FFI) solo para decodificar — evita CameraX/MLKit por completo. `flutter_zxing` no soporta web (usa `dart:ffi`); hay que añadir un guard `kIsWeb` además del guard de escritorio existente para no intentar construir el `ReaderWidget` ahí.

**Regla:** Si un plugin de cámara/ML crashea solo en release y cambiar una opción de configuración del MISMO plugin (bundled/unbundled, versión mayor) reproduce el MISMO patrón de crash en un sitio distinto — no es una casualidad, es que el bug vive en la capa nativa compartida entre esas variantes. Tras 2-3 intentos de configuración fallidos con el mismo patrón, dejar de tocar ese plugin y cambiar a uno con una implementación nativa fundamentalmente distinta (aquí: CameraX/MLKit → `camera` oficial + zxing-cpp). No hace falta lograr un stack trace perfecto para tomar esa decisión si el patrón de fallo se repite de forma idéntica entre variantes.

---

## Patrón general: errores en cascada

Cuando Flutter lanza múltiples errores en secuencia:
```
Exception 1: A TextEditingController was used after being disposed
Exception 2: A RenderFlex overflowed by 99426 pixels
Exception 3: Assertion failed: _dependents.isEmpty is not true
```

**El error real es siempre el PRIMERO.** Los siguientes son cascadas del estado inconsistente. Investigar y corregir solo el primero; los demás desaparecen solos.
