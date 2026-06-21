CREATE TABLE IF NOT EXISTS inspections (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id               UUID NOT NULL REFERENCES machines(id),
  technician_id            UUID NOT NULL REFERENCES users(id),
  status                   TEXT NOT NULL CHECK (status IN ('operative','out_of_service','in_repair')),
  card_reader_ok           BOOLEAN NOT NULL,
  card_reader_failure_type TEXT CHECK (card_reader_failure_type IN ('no_lee','error_comunicacion','dano_fisico','otro')),
  comment                  TEXT,
  inspected_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inspections_machine ON inspections(machine_id, inspected_at DESC);
CREATE INDEX IF NOT EXISTS idx_inspections_technician ON inspections(technician_id);
