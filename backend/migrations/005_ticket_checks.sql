CREATE TABLE IF NOT EXISTS ticket_checks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id UUID NOT NULL UNIQUE REFERENCES inspections(id) ON DELETE CASCADE,
  dispenser_ok  BOOLEAN NOT NULL,
  ticket_level  TEXT NOT NULL CHECK (ticket_level IN ('full','low','empty'))
);
