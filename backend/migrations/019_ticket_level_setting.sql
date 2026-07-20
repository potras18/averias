INSERT INTO settings (key, value) VALUES
  ('ticket_level_question_enabled', 'true')
ON CONFLICT (key) DO NOTHING;
