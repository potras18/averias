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

**Inicio de sesión biométrico *(solo móvil)*:** tras un primer login con email y contraseña, la app ofrece activar el desbloqueo por huella o reconocimiento facial. En los siguientes accesos basta con la biometría; las credenciales quedan guardadas de forma segura en el dispositivo.

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

### Histórico

Vista de consulta del histórico completo de cualquier máquina (activa o inactiva). Accesible desde el menú "Histórico".

**Filtros:**
- **Buscar máquina:** campo de texto para filtrar por nombre.
- **Por ubicación:** desplegable con todas las localizaciones.

**Detalle de máquina seleccionada:**
- En escritorio, se muestra a la derecha al seleccionar una máquina de la lista; en móvil, al pulsar sobre ella.
- Historial de inspecciones (paginado) con técnico, fecha, estado y datos del lector/tickets.
- Historial de repuestos solicitados para esa máquina, con su estado.

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
- **Enviar por email:** envía el PDF a los destinatarios configurados en Ajustes. Si no hay destinatarios configurados, muestra un aviso indicando que hay que añadirlos primero.

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
- Filtro por estado en la parte superior: **Todos / Pendiente / Pedido / Recibido / Instalado**.
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
| **Instalado** | Montado en la máquina; solicitud completada |

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

También permite generar un PDF de estadísticas o enviarlo por email a los destinatarios configurados en Ajustes.

---

### Panel de administración *(solo admins)*

Cuatro pestañas: Localizaciones, Máquinas, Usuarios y Ajustes.

#### Localizaciones
- Crear nueva localización (nombre + dirección).
- Editar nombre o dirección.
- Eliminar localización.

#### Máquinas
- Listar todas las máquinas (activas e inactivas con el interruptor).
- Crear máquina: nombre, localización, si tiene dispensador de tickets.
- Editar datos de una máquina.
- Descargar etiqueta QR en PDF para imprimir (por máquina, desde su ficha).
- **Descargar PDF con los QR de todas las máquinas activas** (botón PDF en la cabecera): genera un único documento A4 con 12 códigos QR por página, cada uno con el nombre de la máquina debajo. Ignora el filtro "Inactivas" — solo incluye máquinas activas.
- Dar de baja una máquina (pasa a inactiva; no se elimina).

#### Usuarios
- Listar usuarios activos e inactivos.
- **Crear usuario:** nombre, email, contraseña (mín. 6 caracteres), rol (admin / técnico).
- **Editar usuario:** nombre, email, contraseña (opcional al editar).
- **Cambiar rol:** admin ↔ técnico. Bloquea si solo queda un admin activo.
- **Desactivar cuenta:** la cuenta pasa a inactiva (no se elimina). Bloquea si es tu propia cuenta o el último admin activo.

> **Regla de seguridad:** siempre debe existir al menos un usuario administrador activo. El sistema impide cualquier acción que lo viole.

#### Ajustes *(solo admins)*

Configuración del correo: servidor SMTP, destinatarios y plantillas de los emails. La pantalla se divide en secciones visualmente separadas (tarjetas con título e icono).

**Servidor SMTP:**
- Host, puerto, usuario, contraseña y dirección de envío (from).
- Si los campos están vacíos, el sistema usa la configuración del `.env` del servidor.
- La contraseña guardada aparece como `***`; déjala en blanco al guardar para no modificarla. Se almacena cifrada en la base de datos.

**Destinatarios:**
- Lista de direcciones de email a las que se enviarán automáticamente los informes y estadísticas.
- Añadir con el campo de texto + botón Añadir. Eliminar pulsando la × del chip.
- Si la lista está vacía, el botón "Enviar por email" en Informes y Estadísticas mostrará un aviso.

**Plantilla de email — Informes** y **Plantilla de email — Estadísticas:**
- Asunto y cuerpo editables para cada tipo de envío (informes y estadísticas por separado).
- Admiten variables que se sustituyen al enviar: `{fecha}`, `{rango}`, `{tecnico}`, `{archivo}`.
- Si se dejan en blanco, se usan los textos por defecto.

Pulsar **Guardar** aplica todos los cambios (SMTP + destinatarios + plantillas) en un solo paso.
