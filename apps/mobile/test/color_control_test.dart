import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/color_control.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('device mode governs initial RGB, including enhanced hue and true zero', () {
    final color = DirectColorState.fromMap(<String,int>{'capabilities': 9,
      'mode': 0, 'hue': 0, 'saturation': 254, 'x': 1, 'y': 1});
    expect(color.hsv!.toColor(), const Color(0xffff0000));
    expect(color.merge(DirectColorState.fromMap(<String,int>{'saturation': 0}))
        .hsv!.toColor(), const Color(0xffffffff));
    expect(DirectColorState.fromMap(<String,int>{'capabilities': 3,
      'enhancedMode': 3, 'enhancedHue': 32768, 'saturation': 254}).hsv!.hue, 180);
    expect(DirectColorState.fromMap(<String,int>{'capabilities': 9,
      'mode': 2, 'hue': 0, 'saturation': 254}).hsv, isNull);
    expect(DirectColorState.fromMap(<String,int>{'capabilities': 16}).supportsColor, isFalse);
    expect(DirectColorState.fromMap(<String,Object?>{'capabilities': 1,
      'mode': 0, 'hue': null, 'saturation': 254}).hsv, isNull);
  });
  test('xy conversion covers sRGB primaries, white and invalid coordinates', () {
    final red = hsvToXy(const HSVColor.fromAHSV(1,0,1,1));
    expect(red.x / 65536, closeTo(0.64, 0.002));
    expect(red.y / 65536, closeTo(0.33, 0.002));
    for (final hue in <double>[0,60,120,180,240,300]) {
      final xy = hsvToXy(HSVColor.fromAHSV(1,hue,1,1));
      final restored = xyToHsv(xy.x,xy.y);
      final delta = (restored.hue - hue + 180) % 360 - 180;
      expect(delta.abs(), lessThan(2));
      expect(restored.saturation, greaterThan(0.98));
    }
    final white = hsvToXy(const HSVColor.fromAHSV(1,0,0,1));
    expect(xyToHsv(white.x,white.y).saturation, lessThan(0.01));
    expect(DirectColorState.fromMap(<String,int>{'capabilities': 8,
      'mode': 1, 'x': 0, 'y': 0}).hsv, isNull);
    expect(() => DirectColorState.fromMap(<String,int>{'hue': 255}), throwsFormatException);
  });
  test('persists names and capability only; old installations remain compatible', () {
    final device = DirectMatterDevice.fromJson(<String,Object?>{
      'nodeId': 7, 'name': 'کلید', 'onOffEndpoints': <int>[3,1],
      'channelNames': <String,String>{'1': 'خروجی ۱ اتاق کودک'},
    });
    expect(device.colorCapabilities, isEmpty);
    final restored = DirectMatterDevice.fromJson(device.copyWith(
      colorCapabilities: <int,int>{1: 9}, onOffEndpoints: <int>[1,3]).toJson());
    expect(restored.channelName(1,0), 'خروجی ۱ اتاق کودک');
    expect(restored.colorCapabilities, <int,int>{1: 9});
    expect(restored.toJson().containsKey('colors'), isFalse);
  });

  const channel = MethodChannel('test/manisa/color');
  const controller = PlatformDirectMatterController(methods: channel);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('bridge decodes actual capability and routes bounded HS/XY to exact endpoint', () async {
    final commands = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readColors') return <String,Object?>{
        '4': <String,Object?>{'capabilities': 1, 'mode': 0, 'hue': 0, 'saturation': 254},
        '5': <String,Object?>{'capabilities': 16},
      };
      commands.add(call.arguments);
      return null;
    });
    expect((await controller.readColors(42)).keys, <int>[4]);
    await controller.setColor(nodeId: 42, endpoint: 4, mode: 'hs', first: 0, second: 254);
    expect(commands.single, <String,Object?>{'nodeId': 42, 'endpoint': 4,
      'mode': 'hs', 'first': 0, 'second': 254});
    expect(() => controller.setColor(nodeId: 42, endpoint: 4,
      mode: 'hs', first: 255, second: 254), throwsArgumentError);
    expect(() => controller.setColor(nodeId: 42, endpoint: 4,
      mode: 'xy', first: 1, second: 0), throwsArgumentError);
  });
}
