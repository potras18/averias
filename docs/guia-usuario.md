# Guía de usuario

## Roles

| Rol | Permisos |
|-----|----------|
| **Técnico** | Consultar máquinas, crear inspecciones, ver informes y estadísticas, gestionar repuestos |
| **Administrador** | Todo lo anterior + gestionar usuarios, localizaciones y máquinas, eliminar repuestos |

---

## Acceso a la aplicación

### Inicio de sesión

Introduce tu email y contraseña en la pantalla de inicio. El sistema bloquea usuarios inactivos aunque tengan credenciales correctas.

- Límite: 5 intentos fallidos por 15 minutos (protección anti-fuerza bruta).
- La sesión dura 8 horas. Al expirar, la app renueva el token automáticamente; si falla, redirige al login.

---

## Pantallas

### Lista de máquinas

Vista principal. Muestra todas las máquinas activas con su estado y fecha de última inspección.

**Filtros disponibles:**
- **Por localización:** desplegable con todas las localizaciones.
- **Máquinas inactivas:** interruptor "Inactivas" para mostrar máquinas dadas de baja.
- **Por fecha de inspección:** filtra máquinas inspeccionadas en una fecha concreta.

**Estados posibles de una máquina:**
| Estado | Significado |
|--------|-------------|
| Operativa | Funcionando con normalidad |
| Fuera de servicio | No funciona |
| En reparación | En proceso de reparación |

---

### Detalle de máquina *(solo móvil)*

Muestra la información completa de una máquina en dos pestañas:

**Pestaña Inspecciones:**
- Nombre, localización, estado actual.
- Código QR de la máquina (para imprimir etiquetas).
- Historial de las últimas 5 inspecciones con técnico y fecha.
- Si la máquina tiene dispensador de tickets: estado del dispensador y nivel de tickets en cada revisión.

**Pestaña Repuestos:**
- Lista de solicitudes de repuestos para esta máquina.
- Botón "+" para crear una nueva solicitud con la máquina preseleccionada.

---

### Escáner QR *(solo móvil)*

Escanea el código QR de una máquina para navegar directamente a su detalle. No disponible en escritorio.

---

### Formulario de inspección *(solo móvil)*

Para registrar una inspección nueva:

1. **Estado:** Operativa / Fuera de servicio / En reparación.
2. **Lector de tarjetas:** ¿Funciona? Si no, seleccionar tipo de fallo:
   - No lee
   - Error de comunicación
   - Daño físico
   - Otro
3. **Comentario** (opcional).
4. **Revisión de tickets** (solo si la máquina tiene dispensador):
   - ¿Dispensador OK?
   - Nivel de tickets: Lleno / Bajo / Vacío

La inspección queda asociada al técnico que ha iniciado sesión.

---

### Informes

Genera informes PDF de inspecciones por periodo y localización.

**Modos de periodo:**

| Modo | Selector | Uso |
|------|----------|-----|
| **Día** | Seleccionar fecha | Informe de un día concreto |
| **Mes** | Mes + año | Informe mensual completo |
| **Rango** | Fecha inicio – fecha fin | Periodo personalizado |

**Filtro de localización:** opcional; sin selección incluye todas.

**Acciones:**
- **Generar PDF:** descarga el informe como archivo PDF.
- **Enviar por email:** introduce una o varias direcciones separadas por coma y envía el PDF.

**Contenido del informe:**
- Resumen: total de máquinas inspeccionadas, porcentajes por estado.
- MTTR (tiempo medio de reparación en horas).
- Top 5 máquinas con más averías.
- Desglose por localización.

---

### Repuestos

Sección para gestionar solicitudes de compra de piezas o repuestos para las máquinas. Accesible para técnicos y administradores.

**Vista de lista:**
- Muestra todas las solicitudes con máquina, descripción, cantidad, estado y creador.
- Filtro por estado en la parte superior: **Todos / Pendiente / Pedido / Recibido**.
- Botón "+" para crear una nueva solicitud.
- Botón de edición en cada ítem para modificar descripción, cantidad o avanzar el estado.
- Solo los administradores ven el botón de eliminación.

**Formulario de creación:**
- Seleccionar máquina.
- Descripción del repuesto (texto libre).
- Cantidad (mínimo 1).

**Formulario de edición:**
- Los mismos campos más el selector de estado.

**Ciclo de vida de una solicitud:**

| Estado | Significado |
|--------|-------------|
| **Pendiente** | Solicitado, aún no pedido al proveedor |
| **Pedido** | Encargado al proveedor |
| **Recibido** | Ya en el local, listo para instalar |

Cualquier usuario (técnico o admin) puede crear solicitudes y cambiar el estado. Solo los administradores pueden eliminarlas.

---

### Estadísticas

Panel con métricas agregadas del periodo seleccionado.

**Filtros:** mismo selector de periodo (día / mes / rango) y localización opcional.

**Datos mostrados:**
- MTTR en horas.
- Porcentaje operativas / fuera de servicio / en reparación.
- Total de máquinas.
- Gráfico de tendencia diaria.
- Top 5 máquinas más problemáticas.
- Estadísticas del lector de tarjetas (% OK / fallo, tipo de fallo más frecuente).
- Estadísticas del dispensador de tickets (% revisado, niveles lleno / bajo / vacío).

También permite generar un PDF de estadísticas o enviarlo por email.

---

### Panel de administración *(solo admins)*

Tres pestañas:

#### Localizaciones
- Crear nueva localización (nombre + dirección).
- Editar nombre o dirección.
- Eliminar localización.

#### Máquinas
- Listar todas las máquinas (activas e inactivas con el interruptor).
- Crear máquina: nombre, localización, si tiene dispensador de tickets.
- Editar datos de una máquina.
- Descargar etiqueta QR en PDF para imprimir.
- Dar de baja una máquina (pasa a inactiva; no se elimina).

#### Usuarios
- Listar usuarios activos e inactivos.
- **Crear usuario:** nombre, email, contraseña (mín. 6 caracteres), rol (admin / técnico).
- **Editar usuario:** nombre, email, contraseña (opcional al editar).
- **Cambiar rol:** admin ↔ técnico. Bloquea si solo queda un admin activo.
- **Desactivar cuenta:** la cuenta pasa a inactiva (no se elimina). Bloquea si es tu propia cuenta o el último admin activo.

> **Regla de seguridad:** siempre debe existir al menos un usuario administrador activo. El sistema impide cualquier acción que lo viole.
