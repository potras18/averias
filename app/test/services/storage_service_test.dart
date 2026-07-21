// app/test/services/storage_service_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> fakeStore = {};

  setUp(() {
    fakeStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      final args = (call.arguments as Map).cast<String, dynamic>();
      switch (call.method) {
        case 'read':
          return fakeStore[args['key'] as String];
        case 'write':
          fakeStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          fakeStore.remove(args['key'] as String);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final storage = StorageService();

  test('getSelectedLocationId returns null when nothing stored', () async {
    expect(await storage.getSelectedLocationId(), isNull);
  });

  test('setSelectedLocationId stores a value that getSelectedLocationId retrieves', () async {
    await storage.setSelectedLocationId('loc-42');
    expect(await storage.getSelectedLocationId(), 'loc-42');
  });

  test('setSelectedLocationId(null) clears a previously stored value', () async {
    await storage.setSelectedLocationId('loc-42');
    await storage.setSelectedLocationId(null);
    expect(await storage.getSelectedLocationId(), isNull);
  });

  test('clear() removes the selected location id along with other session keys', () async {
    await storage.setSelectedLocationId('loc-42');
    await storage.clear();
    expect(await storage.getSelectedLocationId(), isNull);
  });
}
