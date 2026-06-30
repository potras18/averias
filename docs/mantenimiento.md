# Mantenimiento

## Migraciones de base de datos

Las migraciones están en `backend/migrations/` y se ejecutan en orden numérico.

```bash
cd backend
npm run migrate
```

El script (`backend/migrations/run.js`) aplica solo las migraciones pendientes; es idempotente y seguro de ejecutar varias veces.

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
  role VARCHAR(20)       -- 'admin' | 'technician'
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
  status TEXT                -- 'pendiente' | 'pedido' | 'recibido'
  created_by UUID → users
  updated_by UUID → users    -- nullable
  created_at TIMESTAMPTZ
  updated_at TIMESTAMPTZ
```

---

## Gestión de usuarios

Toda la gestión de usuarios se realiza desde el Panel de administración (pestaña Usuarios).

**Operaciones disponibles:**
- Crear usuario (admin o técnico).
- Editar nombre, email y contraseña.
- Cambiar rol entre admin y técnico.
- Desactivar cuenta (nunca se borran; se mantiene el histórico de inspecciones).

**Regla crítica:** debe existir siempre al menos un usuario administrador activo. El sistema bloquea cualquier acción que lo violaría.

**Reactivar una cuenta desactivada:** actualmente no hay opción en la UI. Hacerlo directamente en BD:

```sql
UPDATE users SET active = true WHERE email = 'email@ejemplo.com';
```

---

## Tokens de sesión expirados

Los refresh tokens expiran a las 24 horas. Los tokens caducados no se limpian automáticamente. Para limpiarlos:

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

El envío de emails usa Nodemailer. Si el email falla revisar:

1. Variables de entorno `SMTP_*` en `backend/.env`.
2. Puerto: 587 usa STARTTLS, 465 usa SSL/TLS directo.
3. Si usas Gmail: activar verificación en dos pasos y generar una "contraseña de aplicación" específica.
4. Logs del servidor: `pm2 logs averias-backend` o `journalctl -u averias-backend`.

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
- **CORS:** actualmente permite todos los orígenes. Restringir en producción editando `backend/src/app.js` con la URL de la app.
- **Rate limiting:** el endpoint de login limita a 5 intentos por IP en 15 minutos. Ajustable en `backend/src/routes/auth.js`.
- **Contraseñas:** almacenadas con bcrypt (coste 10). No se almacenan en claro en ningún punto.
