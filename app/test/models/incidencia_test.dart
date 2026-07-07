import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/incidencia.dart';

Map<String, dynamic> _json({String status = 'open', String? resolvedAt}) => {
      'id': 'inc-1',
      'machine_id': 'm-1',
      'machine_name': 'Maquina 1',
      'location_name': 'Local A',
      'reported_by_name': 'Cliente',
      'machine_problem_type': 'no_enciende',
      'card_reader_problem_type': null,
      'comment': 'No arranca',
      'status': status,
      'created_at': '2026-07-07T10:00:00.000Z',
      'resolved_at': resolvedAt,
      'resolution': resolvedAt != null ? 'operative' : null,
    };

void main() {
  test('parses an open incidencia', () {
    final inc = Incidencia.fromJson(_json());
    expect(inc.status, 'open');
    expect(inc.machineName, 'Maquina 1');
    expect(inc.machineProblemType, 'no_enciende');
    expect(inc.resolvedAt, isNull);
  });

  test('parses a resolved incidencia with resolution + resolvedAt', () {
    final inc = Incidencia.fromJson(_json(status: 'resolved', resolvedAt: '2026-07-08T12:00:00.000Z'));
    expect(inc.status, 'resolved');
    expect(inc.resolution, 'operative');
    expect(inc.resolvedAt, isNotNull);
  });
}
