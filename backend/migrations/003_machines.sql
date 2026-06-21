CREATE TABLE IF NOT EXISTS machines (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id            UUID REFERENCES locations(id),
  name                   TEXT NOT NULL,
  qr_code                TEXT UNIQUE NOT NULL,
  has_redemption_tickets BOOLEAN NOT NULL DEFAULT false,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_machines_location ON machines(location_id);
CREATE INDEX IF NOT EXISTS idx_machines_qr ON machines(qr_code);
