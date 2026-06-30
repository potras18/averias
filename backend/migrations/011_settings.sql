CREATE TABLE IF NOT EXISTS settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO settings (key, value) VALUES
  ('smtp_host',        ''),
  ('smtp_port',        '587'),
  ('smtp_user',        ''),
  ('smtp_pass',        ''),
  ('smtp_from',        ''),
  ('email_recipients', '[]')
ON CONFLICT (key) DO NOTHING;
