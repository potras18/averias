CREATE TABLE IF NOT EXISTS locations (
  id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name    TEXT NOT NULL,
  address TEXT
);
