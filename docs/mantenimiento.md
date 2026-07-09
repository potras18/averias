# Mantenimiento

## Migraciones de base de datos

Las migraciones están en `backend/migrations/` y se ejecutan en orden numérico.

```bash
cd backend
npm run migrate
```

El script (`backend/migrations/run.js`) ejecuta **todos** los archivos `.sql` en orden numérico cada vez (no lleva registro de las ya aplicadas). Por eso cada migración debe ser idempotente (`IF NOT EXISTS`, `IF EXISTS`, `ON CONFLICT DO NOTHING`); así es seguro ejecutarlo varias veces.

### Migraciones existentes

| Archivo | Descripción |
|---------|-------------|
| `001_users.sql` | Tabla de usuarios base |
| `002_locations.sql` | Tabla de localizaciones |
| `003_machines.sql` | Tabla de máquinas con índices |
| `004_inspections.sql` | Tabla de inspecciones |
| `005_ticket_checks.sql` | Tabla de revisiones de tickets |
| `006_refresh_tokens.sql` | Tabla de tokens de refresco JWT |
| `007_users_role.sql` | Columna `role` en usuarios |
| `008_machines_active.sql` | Columna `active` en máquinas |
| `009_users_active.sql` | Columna `active` en usuarios |
| `010_spare_parts.sql` | Tabla de repuestos (solicitudes de compra) |
| `011_settings.sql` | Tabla de configuración (SMTP + destinatarios email) |
| `012_email_templates.sql` | Claves de plantillas de email (asunto/cuerpo de informes y estadísticas) |
| `013_spare_parts_instalado.sql` | Añade el estado `instalado` al CHECK de `spare_parts.status` |
| `014_machines_image.sql` | Columnas `image`/`image_mime` en máquinas (foto opcional) |
| `015_users_location.sql` | Columna `location_id` en usuarios (para el rol Cliente/avisos) |
| `016_incidencias.sql` | Tabla de incidencias (avisos de avería de clientes) |
| `017_incidencias_active.sql` | Columna `active` en incidencias (borrado lógico) |

### Añadir una nueva migración

1. Crear `backend/migrations/NNN_descripcion.sql` con el número siguiente en secuencia.
2. Escribir SQL idempotente cuando sea posible (usar `IF NOT EXISTS`, `IF EXISTS`).
3. Ejecutar `npm run migrate` en el servidor.

---

## Esquema de base de datos

```
users
  id UUID PK
  name TEXT
  email TEXT UNIQUE
  password_hash TEXT
  role VARCHAR(20)       -- 'admin' | 'technician' | 'reportes' (cliente/avisos)
  location_id UUID → locations   -- solo se usa con role='reportes'
  active BOOLEAN         -- false = cuenta desactivada
  created_at TIMESTAMPTZ

locations
  id UUID PK
  name TEXT
  address TEXT

machines
  id UUID PK
  location_id UUID → locations
  name TEXT
  qr_code TEXT UNIQUE
  has_redemption_tickets BOOLEAN
  active BOOLEAN         -- false = dada de baja
  image BYTEA            -- foto opcional
  image_mime TEXT
  created_at TIMESTAMPTZ

inspections
  id UUID PK
  machine_id UUID → machines
  technician_id UUID → users
  status TEXT            -- 'operative' | 'out_of_service' | 'in_repair'
  card_reader_ok BOOLEAN
  card_reader_failure_type TEXT  -- 'no_lee' | 'error_comunicacion' | 'dano_fisico' | 'otro'
  comment TEXT
  inspected_at TIMESTAMPTZ
  -- Sin columna active: el borrado (solo admin) es FÍSICO, no lógico. Bloqueado
  -- (409) si la inspección está referenciada por una incidencia activa
  -- (incidencias.open_inspection_id / resolve_inspection_id).

incidencias
  id UUID PK
  machine_id UUID → machines
  reported_by UUID → users          -- el cliente (role='reportes') que reportó
  machine_problem_type TEXT      -- 'no_enciende' | 'no_acepta_pago' | 'pantalla' | 'mecanico' | 'no_entrega_premio' | 'otro'
  card_reader_problem_type TEXT  -- 'no_lee' | 'error_comunicacion' | 'dano_fisico' | 'otro'
  comment TEXT
  status TEXT             -- 'open' | 'resolved'
  created_at TIMESTAMPTZ
  resolved_at TIMESTAMPTZ
  resolved_by UUID → users
  resolution TEXT         -- 'operative' | 'in_repair'
  open_inspection_id UUID → inspections     -- inspección creada al reportar (deja la máquina fuera de servicio)
  resolve_inspection_id UUID → inspections  -- inspección creada al resolver
  active BOOLEAN          -- false = borrada (borrado lógico, solo admin). No se puede
                          -- borrar una incidencia abierta; hay que resolverla primero.

ticket_checks
  id UUID PK
  inspection_id UUID → inspections (CASCADE DELETE)
  dispenser_ok BOOLEAN
  ticket_level TEXT      -- 'full' | 'low' | 'empty'

refresh_tokens
  id UUID PK
  user_id UUID → users (CASCADE DELETE)
  token_hash TEXT UNIQUE
  expires_at TIMESTAMPTZ
  created_at TIMESTAMPTZ

spare_parts
  id UUID PK
  machine_id UUID → machines
  description TEXT           -- qué repuesto hay que comprar
  quantity INTEGER           -- mínimo 1
  status TEXT                -- 'pendiente' | 'pedido' | 'recibido' | 'instalado'
  created_by UUID → users
  updated_by UUID → users    -- nullable
  created_at TIMESTAMPTZ
  updated_at TIMESTAMPTZ

settings
  key TEXT PK                -- 10 claves fijas:
                             --   smtp_host, smtp_port, smtp_user, smtp_pass, smtp_from,
                             --   email_recipients,
                             --   email_subject_reports, email_body_reports,
                             --   email_subject_stats, email_body_stats
  value TEXT                 -- email_recipients: JSON array ["a@b.com"]
                             -- smtp_pass: cifrado AES-256-GCM (prefijo "enc:")
  updated_at TIMESTAMPTZ
```

---

## Gestión de usuarios

Toda la gestión de usuarios se realiza desde el Panel de administración (pestaña Usuarios).

**Operaciones disponibles:**
- Crear usuario (admin, técnico o cliente/avisos — este último requiere asignar una ubicación).
- Editar nombre, email y contraseña (en clientes, también su ubicación).
- Cambiar rol entre admin y técnico (el rol cliente se fija al crear el usuario, no se puede cambiar después).
- Desactivar cuenta (nunca se borran; se mantiene el histórico de inspecciones).

**Regla crítica:** debe existir siempre al menos un usuario administrador activo. El sistema bloquea cualquier acción que lo violaría.

**Reactivar una cuenta desactivada:** actualmente no hay opción en la UI. Hacerlo directamente en BD:

```sql
UPDATE users SET active = true WHERE email = 'email@ejemplo.com';
```

---

## Tokens de sesión

- **Access token:** válido 8 horas. Se renueva automáticamente usando el refresh token (la app lo gestiona en segundo plano, el usuario no nota nada).
- **Refresh token:** válido 30 días. Almacenado en BD. Se genera al hacer login con usuario/contraseña o biométrico.
- **Auto-logout:** si el refresh token también ha caducado (>30 días sin usar la app), se limpia la sesión y se redirige a login.

Los tokens caducados no se limpian automáticamente de la BD. Para limpiarlos:

```sql
DELETE FROM refresh_tokens WHERE expires_at < now();
```

Se puede programar como tarea cron diaria:

```bash
# Añadir a crontab
0 3 * * * psql $DATABASE_URL -c "DELETE FROM refresh_tokens WHERE expires_at < now();"
```

---

## Backups

### Backup manual

```bash
# Backup completo
pg_dump averias > backup_$(date +%Y%m%d_%H%M%S).sql

# Restaurar
psql averias < backup_YYYYMMDD_HHMMSS.sql
```

### Backup automatizado (ejemplo con cron)

```bash
# Backup diario a las 2:00 AM, conservar 30 días
0 2 * * * pg_dump $DATABASE_URL > /backups/averias_$(date +%Y%m%d).sql && find /backups -name "averias_*.sql" -mtime +30 -delete
```

---

## Actualización del backend

```bash
cd backend

# 1. Actualizar código (git pull o desplegar nueva versión)
git pull origin main

# 2. Instalar/actualizar dependencias
npm install

# 3. Ejecutar migraciones pendientes
npm run migrate

# 4. Reiniciar servicio
pm2 restart averias-backend
# o: systemctl restart averias-backend
```

---

## PM2 y arranque en boot

El backend corre bajo PM2 (`averias-backend`), gestionado por el servicio systemd `pm2-ubuntu.service` (`ExecStart=pm2 resurrect`, habilitado con `systemctl enable`). Esto es lo que hace que el backend vuelva a arrancar solo si el VPS se reinicia (mantenimiento del proveedor, actualización de kernel, etc.).

**Verificar que está bien configurado:**

```bash
systemctl is-enabled pm2-ubuntu   # debe decir "enabled"
systemctl is-active pm2-ubuntu    # debe decir "active"
pm2 status                        # averias-backend debe estar "online"
```

**Si el backend está caído y la web da 502 "Bad Gateway":** el proceso PM2 murió y nada lo revivió. Diagnosticar:

```bash
pm2 status                                          # ¿aparece averias-backend?
uptime                                               # ¿se reinició el VPS hace poco?
sudo journalctl -xeu pm2-ubuntu --no-pager | tail -40  # ¿por qué falló el servicio?
```

Arranque manual de emergencia si `pm2 status` no muestra el proceso:

```bash
cd ~/averias-backend && pm2 start src/server.js --name averias-backend
pm2 save   # congela la lista de procesos para el próximo `pm2 resurrect`
```

**Si el servicio systemd existe pero falla al reiniciar** (error típico: `Can't open PID file '/home/ubuntu/.pm2/pm2.pid' (yet?)`), es porque el daemon PM2 ya estaba corriendo fuera de systemd cuando se instaló/reinició el servicio. Solución (implica un corte de segundos):

```bash
pm2 kill
sudo systemctl restart pm2-ubuntu
sleep 5 && systemctl is-active pm2-ubuntu && pm2 status
```

**Reinstalar el servicio desde cero** (si `/etc/systemd/system/pm2-ubuntu.service` no existe):

```bash
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu
pm2 save
```

---

## Actualización de la app Flutter

Compilar de nuevo y distribuir:

```bash
cd app
flutter pub get
flutter build apk --dart-define=API_URL=https://tu-servidor.com
```

Distribuir el APK por el canal habitual (MDM, instalación manual, Play Store interno).

---

## Configuración de email (SMTP)

La configuración SMTP se puede gestionar de dos formas (la BD tiene prioridad sobre el `.env`):

1. **Desde la app** *(recomendado)*: Panel de administración → pestaña Ajustes. Los cambios son inmediatos y no requieren reiniciar el backend. Además de SMTP y destinatarios, permite editar las plantillas (asunto/cuerpo) de los emails de informes y estadísticas, con variables `{fecha}`, `{rango}`, `{tecnico}`, `{archivo}`.
2. **Variables de entorno** en `backend/.env`: actúan como fallback si los campos en BD están vacíos.

> **Cifrado de la contraseña SMTP:** `smtp_pass` se guarda cifrada (AES-256-GCM) con una clave derivada de `JWT_SECRET`. Si cambias `JWT_SECRET`, la contraseña almacenada dejará de poder descifrarse y hay que volver a introducirla en Ajustes.

**Diagnóstico si el email falla:**

1. Verificar que haya destinatarios en Ajustes (si la lista está vacía, el botón de envío muestra aviso y no llega ningún email).
2. Puerto: 587 usa STARTTLS, 465 usa SSL/TLS directo. Algunos ISPs bloquean el 587 — probar con 465.
3. Si usas Gmail: activar verificación en dos pasos y generar una "contraseña de aplicación" específica.
4. El timeout de conexión SMTP es 10 segundos. Si expira, el backend devuelve 500.
5. Logs del servidor: `pm2 logs averias-backend` o `journalctl -u averias-backend`.

Verificar configuración SMTP desde línea de comandos:

```bash
node -e "
const nm = require('nodemailer');
require('dotenv').config();
const t = nm.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT) || 587,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
});
t.verify().then(() => console.log('SMTP OK')).catch(console.error);
" 
```

---

## Logs y diagnóstico

### Backend con PM2

```bash
# Ver logs en tiempo real
pm2 logs averias-backend

# Estado del proceso
pm2 status

# Reiniciar
pm2 restart averias-backend
```

### Consultas útiles en BD

```sql
-- Inspecciones del último mes
SELECT i.inspected_at, u.name as tecnico, m.name as maquina, i.status
FROM inspections i
JOIN users u ON u.id = i.technician_id
JOIN machines m ON m.id = i.machine_id
WHERE i.inspected_at > now() - interval '30 days'
ORDER BY i.inspected_at DESC;

-- Máquinas sin inspección en los últimos 7 días
SELECT m.name, l.name as localizacion
FROM machines m
JOIN locations l ON l.id = m.location_id
WHERE m.active = true
  AND m.id NOT IN (
    SELECT DISTINCT machine_id FROM inspections
    WHERE inspected_at > now() - interval '7 days'
  );

-- Usuarios activos
SELECT name, email, role, created_at FROM users WHERE active = true ORDER BY name;
```

---

## Seguridad

- **JWT_SECRET:** cambiar a una cadena aleatoria de al menos 32 caracteres en producción. Nunca usar el valor de ejemplo.
- **HTTPS:** desplegar el backend detrás de un proxy inverso (nginx, caddy) con TLS en producción.
- **CORS:** controlado por la variable `CORS_ORIGINS` (lista separada por comas). Si está vacía, se **deniegan** las peticiones cross-origin. En producción, ponerla con la(s) URL(s) de la app web: `CORS_ORIGINS=https://app.tudominio.com`.
- **Rate limiting:** el endpoint de login limita a 5 intentos por IP en 15 minutos. Ajustable en `backend/src/routes/auth.js`.
- **Contraseñas:** almacenadas con bcrypt (coste 10). No se almacenan en claro en ningún punto.

---

## Identidad corporativa (tema y tipografía)

La app sigue el manual de identidad de Grupo Cocamatic (`MANUAL IDENTIDAD CORPORATIVA - GRUPO COCAMATIC.pdf` en la raíz del repo).

**Colores corporativos:**

| Color | Pantone | HEX | Uso en la app |
|-------|---------|-----|---------------|
| Naranja | 1235 C | `#F6B734` | `primary` (botones, AppBar, sidebar, acentos) |
| Gris | Cool Gray 8 C | `#808080` | `secondary` |
| Casi negro | — | `#1A1A1A` | `onPrimary` (texto/iconos sobre naranja) |

> El texto sobre el naranja va en oscuro (`#1A1A1A`), no en blanco: el blanco sobre `#F6B734` no cumple contraste accesible.

**Superficies:** fondos y superficies en **blanco** (`surface` y contenedores forzados a blanco / gris muy claro). No se usa el tinte crema que Material 3 derivaría del color semilla naranja. Solo naranja (principal) y gris (secundario) como colores de marca.

**Tipografía:** el manual usa **Calibri** (propietaria de Microsoft). Se sustituye por **Carlito**, fuente libre métricamente compatible, empaquetada como asset en `app/fonts/Carlito-*.ttf` (4 pesos) y declarada en `pubspec.yaml`. Se aplica globalmente vía `fontFamily: 'Carlito'`. La fuente *Days* del manual solo aplica al logotipo (imagen), no a la interfaz.

**Logotipo:** `app/assets/images/cocamatic-logo.png` (versión positiva: texto y símbolo en negro, fondo transparente, recortado a los límites del logo). Se usa en el sidebar de escritorio (`web_shell.dart`, negro sobre naranja) y en el login (`login_screen.dart`, negro sobre blanco). El negro contrasta bien sobre ambos fondos.

**Dónde se define:** todo el tema vive en `app/lib/theme.dart` (`cocamaticTheme()`), usado en `app/lib/app.dart`. Para ajustar colores o fuente, editar solo ese fichero. Las constantes `kBrandOrange`, `kBrandGray`, `kOnBrandOrange` están exportadas para reutilizarlas en widgets.

**Patrones de UI reutilizables:**

- `app/lib/widgets/section_card.dart` (`SectionCard`): tarjeta con cabecera (icono + título), divisor y contenido. Separa visualmente secciones en vistas con scroll. Se usa en Ajustes, detalle de máquina (escritorio y móvil) e Histórico. Al cambiarlo, cambian todas a la vez.
- `app/lib/widgets/confirm_dialog.dart` (`showConfirmDialog`): diálogo de confirmación estándar con título, mensaje y botones centrados. Todos los popups de confirmación (eliminar, dar de baja, desactivar, activar huella) pasan por aquí.
