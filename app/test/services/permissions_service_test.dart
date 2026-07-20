import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/services/permissions_service.dart';

void main() {
  final perms = PermissionsService.instance;

  setUp(() => perms.reset());

  test('admin puede todo', () {
    perms.debugSet('admin', {});
    expect(perms.can('estadisticas.view'), true);
    expect(perms.can('cualquier.cosa'), true);
  });

  test('technician: sin estadisticas, con informes', () {
    perms.debugSet('technician', {
      'estadisticas.view': false,
      'informes.view': true,
      'maquinas.view': true,
    });
    expect(perms.can('estadisticas.view'), false);
    expect(perms.can('informes.view'), true);
    expect(perms.can('maquinas.view'), true);
  });

  test('gerente: con estadisticas, sin maquinas', () {
    perms.debugSet('gerente', {
      'estadisticas.view': true,
      'maquinas.view': false,
    });
    expect(perms.can('estadisticas.view'), true);
    expect(perms.can('maquinas.view'), false);
  });

  test('clave ausente → false', () {
    perms.debugSet('gerente', {});
    expect(perms.can('lo.que.sea'), false);
  });

  test('landingRoute elige la primera ruta accesible', () {
    perms.debugSet('gerente', {
      'maquinas.view': false,
      'inspecciones.view': true,
      'incidencias.view': true,
      'informes.view': true,
      'estadisticas.view': true,
    });
    expect(perms.landingRoute(), '/history');
  });

  test('landingRoute sin ningún permiso concedido → /no-access', () {
    perms.debugSet('technician', {
      'maquinas.view': false,
      'inspecciones.view': false,
      'incidencias.view': false,
      'informes.view': false,
      'estadisticas.view': false,
      'repuestos.view': false,
      'admin.view': false,
    });
    expect(perms.landingRoute(), '/no-access');
  });
}
