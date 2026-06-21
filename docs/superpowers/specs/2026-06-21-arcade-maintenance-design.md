# Arcade Machine Maintenance Tracker — Design Spec

**Date:** 2026-06-21  
**Status:** Approved  

---

## 1. Problem & Goals

Technicians inspect arcade machines across one or more locations, recording each machine's operational state, card reader status, redemption ticket dispenser status (where applicable), and free-text comments. The current PowerApps solution lacks PDF report generation and advanced statistics. This app replaces it with a cross-platform Flutter app backed by a Node.js API and self-hosted PostgreSQL.

**Goals:**
- Scan machine QR code → open inspection form → save state
- Generate PDF report on demand (filterable by date range and location)
- Send report by email with PDF attachment
- Dashboard with MTTR, fault history, availability rate, and top-problematic-machines ranking

---

## 2. Architecture

```
Flutter App (iOS / Android / Web)
        │ HTTPS REST API (JSON)
Node.js + Fastify (Backend)
        │
PostgreSQL (self-hosted)
```

- **Frontend:** Flutter — single codebase for iOS, Android, and web browser
- **Backend:** Node.js with Fastify framework
- **Database:** PostgreSQL
- **PDF generation:** Puppeteer (HTML → PDF)
- **Email:** Nodemailer
- **QR generation:** `qr_flutter` package (Flutter)
- **QR scanning:** `mobile_scanner` package (Flutter, mobile only)
- **Deployment:** Docker Compose (Node.js + PostgreSQL containers), Nginx reverse proxy, Let's Encrypt SSL, Ubuntu 22.04 VPS

---

## 3. Data Model

```sql
-- Technicians who log in
users (
  id            UUID PRIMARY KEY,
  name          TEXT NOT NULL,
  email         TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT now()
)

-- Physical locations / venues
locations (
  id         UUID PRIMARY KEY,
  name       TEXT NOT NULL,
  address    TEXT
)

-- Individual arcade machines
machines (
  id                      UUID PRIMARY KEY,
  location_id             UUID REFERENCES locations(id),
  name                    TEXT NOT NULL,
  qr_code                 TEXT UNIQUE NOT NULL,  -- scanned or generated ID
  has_redemption_tickets  BOOLEAN NOT NULL DEFAULT false,
  created_at              TIMESTAMPTZ DEFAULT now()
)

-- One record per technician visit per machine
inspections (
  id                       UUID PRIMARY KEY,
  machine_id               UUID REFERENCES machines(id),
  technician_id            UUID REFERENCES users(id),
  status                   TEXT NOT NULL CHECK (status IN ('operative','out_of_service','in_repair')),
  card_reader_ok           BOOLEAN NOT NULL,
  card_reader_failure_type TEXT,   -- null when card_reader_ok = true
  comment                  TEXT,
  inspected_at             TIMESTAMPTZ DEFAULT now()
)

-- Only for machines where has_redemption_tickets = true
ticket_checks (
  id            UUID PRIMARY KEY,
  inspection_id UUID REFERENCES inspections(id) UNIQUE,
  dispenser_ok  BOOLEAN NOT NULL,
  ticket_level  TEXT NOT NULL CHECK (ticket_level IN ('full','low','empty'))
)
```

-- Refresh tokens (one active per user)
refresh_tokens (
  id          UUID PRIMARY KEY,
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now()
)

**Indexes:** `inspections(machine_id, inspected_at DESC)`, `inspections(technician_id)`, `machines(location_id)`, `machines(qr_code)`.

---

## 4. API Endpoints

### Auth
| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/login` | Email + password → JWT + refresh token |
| POST | `/auth/refresh` | Refresh token → new JWT |
| POST | `/auth/logout` | Invalidate refresh token |

### Machines
| Method | Path | Description |
|--------|------|-------------|
| GET | `/machines` | List all machines (filterable by `location_id`) |
| GET | `/machines/:id` | Single machine + last 10 inspections |
| GET | `/machines/qr/:code` | Look up machine by QR code |
| POST | `/machines` | Create machine |
| PUT | `/machines/:id` | Update machine |

### Locations
| Method | Path | Description |
|--------|------|-------------|
| GET | `/locations` | List all locations |
| POST | `/locations` | Create location |

### Inspections
| Method | Path | Description |
|--------|------|-------------|
| POST | `/inspections` | Save inspection (includes ticket_check if applicable) |
| GET | `/inspections` | List inspections (filters: machine_id, location_id, date range) |

### Statistics
| Method | Path | Description |
|--------|------|-------------|
| GET | `/stats/mttr` | Mean time to repair, global and per machine. MTTR = avg time between first `out_of_service` inspection and the next `operative` inspection for the same machine, across all resolved incidents. |
| GET | `/stats/fault-history` | Fault count per machine |
| GET | `/stats/availability` | Availability rate per machine and per location |
| GET | `/stats/top-problematic` | Ranked list by fault count |

### Reports
| Method | Path | Description |
|--------|------|-------------|
| GET | `/reports/pdf` | Generate and return PDF (params: `from`, `to`, `location_id`) |
| POST | `/reports/email` | Generate PDF and send by email |

All endpoints require `Authorization: Bearer <jwt>` except `/auth/login`.

---

## 5. Flutter App — Screens

### User Management
- No self-registration — technician accounts created directly in the database (Phase 1–4)
- Phase 5 candidate: simple admin screen to create/deactivate accounts

### Login
- Email + password form
- JWT stored in `flutter_secure_storage`
- Error messages for wrong credentials or network failure

### Machine List
- Grouped by location
- Status badge per machine: green (operative), red (out_of_service), orange (in_repair)
- Search by name or QR code
- FAB: "Scan QR" (mobile) — opens camera via `mobile_scanner`
- Pull-to-refresh

### Machine Detail / Inspection Form
- Machine name, location, QR code display
- Status selector: Operativa / Fuera de servicio / En reparación
- Card reader section: OK toggle; if NO → dropdown for failure type (no lee / error comunicación / daño físico / otro)
- Ticket redemption section (only shown if `has_redemption_tickets`):
  - Dispensador OK toggle
  - Nivel: Lleno / Bajo / Vacío
- Comment text field (free text)
- "Guardar inspección" button
- Collapsible history: last 10 inspections for this machine

### Machine Management (admin-light)
- Create/edit machine: name, location, has redemption tickets
- Generate QR → preview + download PNG for printing
- Assign existing QR code: manual text input

### Statistics Dashboard
- Date range picker (default: last 30 days)
- MTTR card (global + per-machine table)
- Top-problematic-machines bar chart
- Availability rate per location (percentage)
- Fault history sparklines per machine

### Reports
- Date range selector
- Optional location filter
- "Generar PDF" → downloads file or opens share sheet on mobile
- "Enviar por email" → email input field(s) → sends via backend

---

## 6. PDF Report Structure

1. Header: logo (optional), date range, generation date, technician name
2. Summary table: total machines, % operative, % out of service, % in repair
3. Per-location section:
   - Machine table: name | status | card reader | ticket level | technician | comment | date
4. Statistics section: MTTR, top 5 most problematic machines, availability rate

Generated server-side with Puppeteer from an HTML template. Returned as `application/pdf`.

---

## 7. Security

- Passwords hashed with bcrypt (12 salt rounds)
- JWT expiry: 8h access token, 24h refresh token; refresh tokens stored in DB, invalidated on logout
- HTTPS enforced via Nginx + Let's Encrypt
- Login rate limiting: 5 failed attempts → 15-minute block (per IP)
- All API inputs validated with Fastify schema validation (JSON Schema)
- SQL queries via parameterized statements (pg driver) — no raw string interpolation

---

## 8. Error Handling

| Scenario | Behavior |
|----------|----------|
| QR not found | Prompt: "¿Crear nueva máquina con este código?" |
| Save inspection fails | Auto-retry ×3; then show error with manual retry button |
| PDF generation fails | Show error message with cause |
| Network unavailable | Clear error banner; no silent failure |
| JWT expired | Auto-refresh; if refresh fails → redirect to login |

---

## 9. Deployment

```yaml
# docker-compose.yml (summary)
services:
  db:
    image: postgres:16
    volumes: [pgdata:/var/lib/postgresql/data]
  api:
    build: ./backend
    depends_on: [db]
    environment: [DATABASE_URL, JWT_SECRET, SMTP_*]
  web:
    # Flutter web build served via Nginx
```

- Nginx proxies `/api/*` → Node.js container; `/` → Flutter web static files
- `pg_dump` cron job daily → compressed backup stored locally (+ optional remote copy)
- Environment variables via `.env` file (never committed)

---

## 10. Project Structure

```
averias/
├── backend/
│   ├── src/
│   │   ├── routes/         # auth.js, machines.js, inspections.js, stats.js, reports.js
│   │   ├── db/             # pool.js, queries per domain
│   │   ├── pdf/            # template.html, generator.js (Puppeteer)
│   │   └── email/          # mailer.js (Nodemailer)
│   ├── migrations/         # SQL migration files
│   ├── Dockerfile
│   └── package.json
├── app/
│   ├── lib/
│   │   ├── screens/        # login, machine_list, machine_detail, stats, reports, machine_form
│   │   ├── services/       # api_client.dart, auth_service.dart, qr_service.dart
│   │   └── models/         # machine.dart, inspection.dart, user.dart
│   └── pubspec.yaml
├── docker-compose.yml
└── docs/
    └── superpowers/specs/
        └── 2026-06-21-arcade-maintenance-design.md
```

---

## 11. Delivery Phases

| Phase | Scope |
|-------|-------|
| 1 | Auth + machine CRUD + basic inspection form + QR scan |
| 2 | Card reader fields + redemption ticket section + inspection history |
| 3 | PDF generation + email sending |
| 4 | Statistics dashboard (MTTR, ranking, availability) |
| 5 | QR generation from app + location management UI |

Phases 1–2: functional replacement for PowerApps.  
Phases 3–4: parity + new capabilities.  
Phase 5: additional operational tooling.
