# Infraestructura y recursos

## Requisitos

### Backend

| Requisito | Versión mínima |
|-----------|---------------|
| Node.js | 22.12.0+ (requerido por Puppeteer para generación de PDF) |
| PostgreSQL | 14+ (necesita extensión `pgcrypto`) |
| npm | 9+ |

### Frontend (Flutter)

| Requisito | Versión mínima |
|-----------|---------------|
| Flutter SDK | 3.19.0 |
| Dart | 3.3.0 |
| Android SDK (si se compila para Android) | API 21+ |
| Xcode (si se compila para iOS) | 14+ |

### Servidor de correo (opcional)

Cualquier servidor SMTP con soporte STARTTLS (puerto 587) o SSL (puerto 465). Ejemplos: Gmail con contraseña de aplicación, Mailgun, Resend, servidor propio.

---

## Variables de entorno

Crear el archivo `backend/.env` a partir de `backend/.env.example`:

```env
# Base de datos principal
DATABASE_URL=postgresql://usuario:contraseña@host:5432/averias

# Base de datos de tests (no usar en producción)
TEST_DATABASE_URL=postgresql://usuario:contraseña@host:5432/averias_test

# Clave secreta JWT — mínimo 32 caracteres, aleatoria
JWT_SECRET=cambia-esto-por-una-cadena-aleatoria-larga

# Puerto del servidor (por defecto 3000)
PORT=3000

# Configuración SMTP para envío de emails (fallback)
# Alternativa: configurarlo desde la app en Ajustes (panel de administrador)
SMTP_HOST=smtp.ejemplo.com
SMTP_PORT=587
SMTP_USER=correo@ejemplo.com
SMTP_PASS=contraseña_aplicacion
SMTP_FROM=correo@ejemplo.com
```

> **Seguridad:** `JWT_SECRET` debe ser una cadena aleatoria larga. Nunca usar el valor por defecto en producción.

> **SMTP:** Los valores SMTP del `.env` son un fallback. Si se configuran desde la app (Ajustes → pestaña Ajustes como administrador), tienen prioridad sobre el `.env`.

---

## Instalación inicial

### 1. Base de datos

```bash
# Crear las bases de datos
createdb averias
createdb averias_test   # solo para desarrollo/tests

# Activar extensión pgcrypto (necesaria para gen_random_uuid)
psql averias -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
psql averias_test -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
```

### 2. Backend

```bash
cd backend

# Instalar dependencias
npm install

# Crear y editar el archivo de entorno
cp .env.example .env
# → editar .env con los valores correctos

# Ejecutar migraciones (crea todas las tablas)
npm run migrate

# Iniciar servidor
npm start
# o en modo desarrollo con recarga automática:
npm run dev
```

El servidor escucha en `http://0.0.0.0:3000` (o el `PORT` configurado).

### 3. Primer usuario administrador

Actualmente no hay endpoint público de registro. Para crear el primer admin, insertar directamente en la base de datos:

```bash
# Generar hash de contraseña (desde Node.js)
node -e "const bcrypt = require('bcrypt'); bcrypt.hash('tu_contraseña', 10).then(h => console.log(h));"

# Insertar en la BD
psql averias -c "
  INSERT INTO users (name, email, password_hash, role)
  VALUES ('Nombre Admin', 'admin@ejemplo.com', '<hash_generado>', 'admin');
"
```

Una vez creado el primer admin, los demás usuarios se gestionan desde el Panel de administración.

### 4. App Flutter

```bash
cd app

# Instalar dependencias
flutter pub get

# Ejecutar en dispositivo o emulador conectado
flutter run

# Especificar URL del backend (por defecto: http://localhost:3000)
flutter run --dart-define=API_URL=http://tu-servidor:3000
```

---

## Estructura de puertos

| Servicio | Puerto por defecto |
|----------|--------------------|
| Backend API | 3000 |
| PostgreSQL | 5432 (estándar) / 5433 (desarrollo local habitual) |

---

## Compilar para producción

### App Android

```bash
cd app
flutter build apk --dart-define=API_URL=https://tu-servidor.com
# APK en: build/app/outputs/flutter-apk/app-release.apk
```

> **Importante:** el `AndroidManifest.xml` incluye `INTERNET` y `usesCleartextTraffic`. Si el backend usa HTTPS (recomendado en producción) se puede eliminar `usesCleartextTraffic`. Para desarrollo local con HTTP es necesario.

> **Prueba en red local:** usar la IP del servidor en la red WiFi, no `localhost`. Ejemplo: `--dart-define=API_URL=http://192.168.1.42:3000`.

> **Seguridad en producción:** `usesCleartextTraffic="true"` permite HTTP para desarrollo en red local. En producción, desplegar el backend detrás de un proxy inverso con TLS (nginx + Let's Encrypt) y compilar la app con la URL HTTPS: `--dart-define=API_URL=https://tu-dominio.com`. Una vez en HTTPS, cambiar a `usesCleartextTraffic="false"` en el AndroidManifest.

### App iOS

```bash
cd app
flutter build ios --dart-define=API_URL=https://tu-servidor.com
# Requiere Xcode y cuenta de Apple Developer
```

### App Web

```bash
cd app
flutter build web --dart-define=API_URL=https://tu-servidor.com
# Archivos en: build/web/ — servir con cualquier servidor web estático
```

### Backend

```bash
cd backend
npm start
# o con PM2 para producción:
pm2 start src/server.js --name averias-backend
```

---

## Tests

### Backend

```bash
cd backend
npm test
# Ejecuta todos los tests con Jest + Supertest
# Nota: el test de generación de PDF (pdf-generator.test.js) requiere
# Puppeteer con Chromium instalado; puede fallar en entornos sin navegador.
```

### Flutter

```bash
cd app
flutter test
# Ejecuta los tests de widget con mocktail
```
