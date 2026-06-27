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

## Patrón general: errores en cascada

Cuando Flutter lanza múltiples errores en secuencia:
```
Exception 1: A TextEditingController was used after being disposed
Exception 2: A RenderFlex overflowed by 99426 pixels
Exception 3: Assertion failed: _dependents.isEmpty is not true
```

**El error real es siempre el PRIMERO.** Los siguientes son cascadas del estado inconsistente. Investigar y corregir solo el primero; los demás desaparecen solos.
