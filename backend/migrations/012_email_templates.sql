INSERT INTO settings (key, value) VALUES
  ('email_subject_reports', 'Informe de Averías — {archivo}'),
  ('email_body_reports',    'Adjunto encontrará el informe de averías solicitado.'),
  ('email_subject_stats',   'Estadísticas — {archivo}'),
  ('email_body_stats',      'Adjunto encontrará el reporte de estadísticas solicitado.')
ON CONFLICT (key) DO NOTHING;
