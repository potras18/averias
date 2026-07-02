ALTER TABLE spare_parts DROP CONSTRAINT IF EXISTS spare_parts_status_check;
ALTER TABLE spare_parts ADD CONSTRAINT spare_parts_status_check
  CHECK (status IN ('pendiente', 'pedido', 'recibido', 'instalado'));
