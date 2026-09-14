import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/level_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Matter level and percentage conversion covers valid boundaries', () {
    expect(matterLevelToPercent(1), 1);
    expect(matterLevelToPercent(127), 50);
    expect(matterLevelToPercent(254), 100);
    expect(percentToMatterLevel(1), 3);
    expect(percentToMatterLevel(50), 127);
    expect(percentToMatterLevel(100), 254);
    expect(() => matterLevelToPercent(0), throwsRangeError);
    expect(() => percentToMatterLevel(0), throwsRangeError);
  });

  const channel = MethodChannel('test/manisa/level');
  const controller = PlatformDirectMatterController(methods: channel);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reads supported endpoints while preserving nullable CurrentLevel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readLevels');
      expect(call.arguments, <String, Object?>{'nodeId': 42});
      return <String, Object?>{'1': 127, '2': null};
    });
    expect(await controller.readLevels(42), <int, int?>{1: 127, 2: null});
  });

  test('sends one bounded raw level to the exact endpoint', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.method, 'setLevel');
      expect(call.arguments, <String, Object?>{
        'nodeId': 42, 'endpoint': 7, 'level': 191,
      });
      return null;
    });
    await controller.setLevel(nodeId: 42, endpoint: 7, level: 191);
    expect(calls, 1);
    expect(
      () => controller.setLevel(nodeId: 42, endpoint: 7, level: 255),
      throwsRangeError,
    );
  });

  for (final raw in <Object?>[
    null,
    <String, Object?>{'x': 1},
    <String, Object?>{'1': 0},
    <String, Object?>{'1': 255},
    <String, Object?>{'1': '127'},
  ]) {
    test('rejects malformed CurrentLevel response: $raw', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => raw);
      await expectLater(controller.readLevels(42), throwsFormatException);
    });
  }
}
