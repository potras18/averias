-- backend/migrations/018_role_permissions.sql
CREATE TABLE IF NOT EXISTS role_permissions (
  role TEXT NOT NULL,
  permission_key TEXT NOT NULL,
  allowed BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (role, permission_key)
);

INSERT INTO role_permissions (role, permission_key, allowed) VALUES
  ('technician', 'estadisticas.view', false),
  ('technician', 'informes.view',     true),
  ('technician', 'incidencias.view',  true),
  ('technician', 'incidencias.edit',  true),
  ('technician', 'inspecciones.view', true),
  ('technician', 'inspecciones.edit', true),
  ('technician', 'maquinas.view',     true),
  ('technician', 'maquinas.edit',     false),
  ('technician', 'repuestos.view',    true),
  ('technician', 'repuestos.edit',    false),
  ('technician', 'admin.view',        false),
  ('gerente',    'estadisticas.view', true),
  ('gerente',    'informes.view',     true),
  ('gerente',    'incidencias.view',  true),
  ('gerente',    'incidencias.edit',  false),
  ('gerente',    'inspecciones.view', true),
  ('gerente',    'inspecciones.edit', false),
  ('gerente',    'maquinas.view',     false),
  ('gerente',    'maquinas.edit',     false),
  ('gerente',    'repuestos.view',    false),
  ('gerente',    'repuestos.edit',    false),
  ('gerente',    'admin.view',        false)
ON CONFLICT (role, permission_key) DO NOTHING;
