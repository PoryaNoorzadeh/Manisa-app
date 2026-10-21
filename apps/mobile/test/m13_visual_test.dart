import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/color_control.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/sensor_measurement.dart';

import 'm13_design_test.dart' show TestController, TestDevices;

class VisualDevices extends TestDevices {
  @override
  Future<List<DirectMatterDevice>> load() async => const [
    DirectMatterDevice(
      nodeId: 1,
      name: 'کلید پذیرایی',
      onOffEndpoints: [1],
      channelNames: {1: 'چراغ آویز'},
    ),
    DirectMatterDevice(
      nodeId: 2,
      name: 'سنسور پذیرایی',
      onOffEndpoints: [],
      sensorCapabilities: {
        2: {SensorMetric.temperature, SensorMetric.humidity},
      },
    ),
    DirectMatterDevice(
      nodeId: 3,
      name: 'در ورودی',
      onOffEndpoints: [],
      sensorCapabilities: {
        2: {SensorMetric.contactClosed, SensorMetric.occupancy},
      },
    ),
  ];
}

class VisualController extends TestController
    implements SensorMeasurementController, ColorControlController {
  @override
  Future<Map<int, DirectColorState>> readColors(int nodeId) async => nodeId == 1
      ? {
          1: DirectColorState.fromMap({
            'capabilities': 1,
            'mode': 0,
            'hue': 85,
            'saturation': 254,
          }),
        }
      : {};
  @override
  Future<void> setColor({
    required int nodeId,
    required int endpoint,
    required String mode,
    required int first,
    required int second,
  }) async {}
  @override
  Stream<DirectColorEvent> watchColors() => const Stream.empty();
  @override
  Future<List<int>> discoverOnOffEndpoints(int nodeId) async =>
      nodeId == 1 ? [1] : [];
  @override
  Future<bool> readOnOff({required int nodeId, required int endpoint}) async =>
      true;
  @override
  Future<Map<int, DirectSensorMeasurement>> readSensorMeasurements(
    int nodeId,
  ) async => nodeId == 1
      ? {}
      : {
          2: DirectSensorMeasurement(
            nodeId == 2
                ? {SensorMetric.temperature: 2340, SensorMetric.humidity: 4200}
                : {SensorMetric.contactClosed: 1, SensorMetric.occupancy: 0},
          ),
        };
  @override
  Stream<DirectSensorEvent> watchSensorMeasurements() => const Stream.empty();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Vazirmatn')
          ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'main screens render with real fonts, source readings and three languages',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ManisaDirectApp(
            controller: VisualController(),
            deviceStore: VisualDevices(),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/brand/manisa-brand-source.png'),
          boundary.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        if (!const bool.fromEnvironment('MANISA_CAPTURE')) return;
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = Directory(
            const String.fromEnvironment(
              'MANISA_CAPTURE_DIR',
              defaultValue: '/tmp/manisa-preview',
            ),
          );
          await output.create(recursive: true);
          await File('${output.path}/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      expect(find.text('۲۳٫۴ °C'), findsWidgets);
      await capture('home-fa');
      await tester.ensureVisible(find.byKey(const ValueKey('open-device-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-device-1')));
      await tester.pumpAndSettle();
      await capture('device-power-fa');
      await tester.tap(find.byTooltip('نور و مصرف'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('color-wheel')));
      await tester.pumpAndSettle();
      await capture('device-color-fa');
      Navigator.of(
        tester.element(find.byKey(const ValueKey('device-detail-screen'))),
      ).pop();
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('افزودن'));
      await tester.pumpAndSettle();
      await capture('add-fa');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('کارها').last);
      await tester.pumpAndSettle();
      await capture('tasks-fa');
      await tester.tap(find.text('تنظیمات').last);
      await tester.pumpAndSettle();
      await capture('settings-fa');
      await tester.ensureVisible(find.text('English'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      await capture('settings-en');
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await capture('home-en');
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('العربية'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      await capture('settings-ar');
      await tester.tap(find.text('الرئيسية').last);
      await tester.pumpAndSettle();
      await capture('home-ar');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
