# Averías — Documentación

Sistema de gestión de averías e inspecciones para máquinas de entretenimiento.

## Índice

| Documento | Contenido |
|-----------|-----------|
| [Guía de usuario](guia-usuario.md) | Pantallas, flujos de trabajo, roles de usuario |
| [Infraestructura y recursos](infraestructura.md) | Requisitos, instalación, configuración |
| [Mantenimiento](mantenimiento.md) | Migraciones, backups, gestión de usuarios, actualización, identidad corporativa |

## Resumen del sistema

- **Frontend:** Flutter 3.19+ (móvil y escritorio/web)
- **Backend:** Node.js con Fastify 4 + PostgreSQL
- **Autenticación:** JWT con refresh tokens
- **Informes:** PDF generado con Puppeteer, envío por email vía SMTP
- **Control de acceso:** Roles admin / técnico
