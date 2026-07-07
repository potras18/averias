CREATE TABLE IF NOT EXISTS incidencias (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id                UUID NOT NULL REFERENCES machines(id),
  reported_by               UUID NOT NULL REFERENCES users(id),
  machine_problem_type      TEXT CHECK (machine_problem_type IN
                              ('no_enciende','no_acepta_pago','pantalla','mecanico','no_entrega_premio','otro')),
  card_reader_problem_type  TEXT CHECK (card_reader_problem_type IN
                              ('no_lee','error_comunicacion','dano_fisico','otro')),
  comment                   TEXT,
  status                    TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved')),
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at               TIMESTAMPTZ,
  resolved_by               UUID REFERENCES users(id),
  resolution                TEXT CHECK (resolution IN ('operative','in_repair')),
  open_inspection_id        UUID REFERENCES inspections(id),
  resolve_inspection_id     UUID REFERENCES inspections(id)
);

CREATE INDEX IF NOT EXISTS idx_incidencias_status ON incidencias(status);
CREATE INDEX IF NOT EXISTS idx_incidencias_machine ON incidencias(machine_id);
