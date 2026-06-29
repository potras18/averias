# Averías

Sistema de gestión de averías e inspecciones para máquinas de entretenimiento.

## Documentación

| Documento | Descripción |
|-----------|-------------|
| [Guía de usuario](docs/guia-usuario.md) | Pantallas, flujos de trabajo, roles |
| [Infraestructura y recursos](docs/infraestructura.md) | Requisitos, instalación, variables de entorno, compilación |
| [Mantenimiento](docs/mantenimiento.md) | Migraciones, backups, gestión de usuarios, seguridad |

## Stack

- **Frontend:** Flutter 3.19+ (móvil y escritorio/web)
- **Backend:** Node.js + Fastify 4 + PostgreSQL
- **Auth:** JWT con refresh tokens
- **Informes:** PDF con Puppeteer, email vía SMTP

## Inicio rápido

```bash
# Backend
cd backend && npm install && cp .env.example .env
# → editar .env con DATABASE_URL y JWT_SECRET
npm run migrate && npm start

# App Flutter
cd app && flutter pub get
flutter run --dart-define=API_URL=http://localhost:3000
```

Ver [docs/infraestructura.md](docs/infraestructura.md) para instalación completa.
