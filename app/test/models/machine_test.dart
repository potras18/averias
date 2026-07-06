import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/machine.dart';

Map<String, dynamic> _baseJson({bool? active, bool? hasImage}) => {
  'id': 'x',
  'name': 'M',
  'qr_code': 'QR-X',
  'has_redemption_tickets': false,
  'location_id': null,
  'location_name': null,
  'last_status': null,
  'last_inspected_at': null,
  'inspections': <dynamic>[],
  if (active != null) 'active': active,
  if (hasImage != null) 'has_image': hasImage,
};

void main() {
  test('Machine.fromJson parses active: false', () {
    final m = Machine.fromJson(_baseJson(active: false));
    expect(m.active, isFalse);
  });

  test('Machine.fromJson defaults active to true when key missing', () {
    final m = Machine.fromJson(_baseJson());
    expect(m.active, isTrue);
  });

  test('Machine.fromJson parses active: true', () {
    final m = Machine.fromJson(_baseJson(active: true));
    expect(m.active, isTrue);
  });

  test('Machine.fromJson parses has_image true', () {
    final json = _baseJson(hasImage: true);
    final m = Machine.fromJson(json);
    expect(m.hasImage, isTrue);
  });

  test('Machine.fromJson defaults hasImage to false when key missing', () {
    final m = Machine.fromJson(_baseJson());
    expect(m.hasImage, isFalse);
  });
}
