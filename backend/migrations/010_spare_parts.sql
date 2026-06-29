CREATE TABLE IF NOT EXISTS spare_parts (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id  UUID        NOT NULL REFERENCES machines(id),
  description TEXT        NOT NULL,
  quantity    INTEGER     NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  status      TEXT        NOT NULL DEFAULT 'pendiente'
                          CHECK (status IN ('pendiente', 'pedido', 'recibido')),
  created_by  UUID        NOT NULL REFERENCES users(id),
  updated_by  UUID        REFERENCES users(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON spare_parts (machine_id);
CREATE INDEX ON spare_parts (status);
