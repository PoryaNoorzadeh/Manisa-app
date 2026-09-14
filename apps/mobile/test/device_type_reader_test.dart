import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/manisa/descriptor');
  const controller = PlatformDirectMatterController(methods: channel);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('descriptor bridge preserves node, endpoint and device type identity', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readDeviceTypes');
      expect(call.arguments, <String, Object?>{'nodeId': 42});
      return <String, Object?>{'11': <int>[0x010a], '23': <int>[0x0100]};
    });
    expect(await controller.readDeviceTypes(42), <int, List<int>>{
      11: <int>[0x010a], 23: <int>[0x0100],
    });
  });

  for (final raw in <Object?>[
    null,
    <String, Object?>{'x': <int>[1]},
    <String, Object?>{'1': <String>['266']},
    <String, Object?>{'1': <int>[-1]},
  ]) {
    test('rejects malformed descriptor response: $raw', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => raw);
      await expectLater(controller.readDeviceTypes(42), throwsFormatException);
    });
  }

  test('native read failure remains distinguishable from an empty descriptor', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'matter_descriptor_failed');
    });
    await expectLater(controller.readDeviceTypes(42), throwsA(isA<PlatformException>()));
  });

  const device = DirectMatterDevice(
    nodeId: 7, name: 'وسیله', onOffEndpoints: <int>[11, 23],
    channelNames: <int, String>{11: 'چراغ مطالعه'},
    deviceTypes: <int, List<int>>{11: <int>[0x010a], 23: <int>[0x0100]},
  );

  test('metadata survives JSON reload and endpoint reordering', () {
    final decoded = DirectMatterDevice.fromJson(device.toJson())
        .copyWith(onOffEndpoints: <int>[23, 11]);
    expect(decoded.deviceTypes, device.deviceTypes);
    expect(decoded.channelName(11, 1), 'چراغ مطالعه');
    expect(decoded.isSocket(11), isTrue);
    expect(decoded.isSocket(23), isFalse);
    expect(decoded.productLabel, 'وسیلهٔ ترکیبی');
  });

  test('legacy metadata and unknown types never imply a socket or physical gangs', () {
    final legacy = DirectMatterDevice.fromJson(<String, Object?>{
      'nodeId': 7, 'name': 'وسیله', 'onOffEndpoints': <int>[11, 23],
    });
    expect(legacy.deviceTypes, isEmpty);
    expect(legacy.productLabel, 'کنترل ۲ خروجی مستقل');
    expect(legacy.copyWith(onOffEndpoints: <int>[11]).productLabel, 'کنترل تک‌خروجی');
    expect(legacy.copyWith(deviceTypes: <int, List<int>>{11: <int>[0xffff]}).isSocket(11), isFalse);
    expect(legacy.copyWith(onOffEndpoints: <int>[]).productLabel, 'در انتظار شناسایی خروجی‌ها');
  });

  test('both declared plug-in unit types use the socket presentation', () {
    expect(device.copyWith(deviceTypes: <int, List<int>>{
      11: <int>[0x010a], 23: <int>[0x010b],
    }).productLabel, 'پریز هوشمند');
  });
}
