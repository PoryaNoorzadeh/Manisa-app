import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/color_control.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/electrical_measurement.dart';
import 'package:manisa_mobile/src/matter/favorite_store.dart';
import 'package:manisa_mobile/src/matter/home_profile_store.dart';
import 'package:manisa_mobile/src/matter/room_store.dart';

void main() {
  testWidgets('direct output edit persists by endpoint and preserves other names', (tester) async {
    final controller = _Controller()..discovery.complete(<int>[2,1]);
    final store = _RenameStore()..fail = false;
    store.device = store.device.copyWith(onOffEndpoints: <int>[2,1],
      channelNames: <int,String>{2: 'راهرو'});
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('rename-output-7-1'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('یک نام برای خروجی بنویس.'), findsOneWidget);
    store.fail = true;
    await tester.enterText(find.byType(TextField), 'خروجی ۱ اتاق کودک');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('نام ذخیره نشد. دوباره تلاش کن.'), findsOneWidget);
    expect(store.device.channelNames[1], isNull);
    store.fail = false;
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(store.device.channelNames, <int,String>{2: 'راهرو', 1: 'خروجی ۱ اتاق کودک'});
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
    await tester.pumpAndSettle();
    expect(find.text('خروجی ۱ اتاق کودک'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.events.close();
  });

  testWidgets('RGB starts with device color, sends once, confirms and merges live reports', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800,1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _ColorController()..discovery.complete(<int>[1]);
    final store = _RenameStore()..fail = false;
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
    await tester.pumpAndSettle();
    expect(find.text('رنگ نور'), findsOneWidget);
    expect(controller.colorCommands, isEmpty);
    expect(store.device.colorCapabilities, <int,int>{1: 1});
    Slider hueSlider() => tester.widget<Slider>(find.byKey(const ValueKey('color-hue')));
    expect(hueSlider().value, closeTo(169*360/254, 0.001));
    hueSlider().onChanged!(120);
    await tester.pump();
    expect(controller.colorCommands, isEmpty);
    hueSlider().onChangeEnd!(120);
    await tester.pumpAndSettle();
    expect(controller.colorCommands.single, <Object>[7,1,'hs',85,254]);
    expect(hueSlider().value, closeTo(42*360/254, 0.001)); // device clamps command
    controller.colorEvents.add(DirectColorEvent(nodeId: 7,endpoint: 9,
      report: DirectColorState.fromMap(<String,int>{'hue': 0})));
    await tester.pumpAndSettle();
    expect(hueSlider().value, closeTo(42*360/254, 0.001));
    controller.colorEvents.add(DirectColorEvent(nodeId: 7,endpoint: 1,
      report: DirectColorState.fromMap(<String,int>{'hue': 100})));
    await tester.pumpAndSettle();
    expect(hueSlider().value, closeTo(100*360/254, 0.001));
    controller.failColor = true;
    hueSlider().onChangeEnd!(60);
    await tester.pumpAndSettle();
    expect(find.text('رنگ نیاز به به‌روزرسانی دارد'), findsOneWidget);
    expect(hueSlider().value, closeTo(100*360/254, 0.001));
    expect(hueSlider().onChanged, isNull);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.colorEvents.add(DirectColorEvent(nodeId: 7,endpoint: 1,
      report: DirectColorState.fromMap(<String,int>{'hue': 0})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await controller.events.close();
    await controller.levelEvents.close();
    await controller.colorEvents.close();
  });

  testWidgets('late color refresh cannot overwrite a newer device report', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800,1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _ColorController()..discovery.complete(<int>[1]);
    await tester.pumpWidget(ManisaDirectApp(controller: controller,
      deviceStore: _RenameStore()..fail = false));
    await tester.pumpAndSettle();
    final pending = Completer<Map<int, DirectColorState>>();
    controller.pendingColorRead = pending;
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();
    controller.colorEvents.add(DirectColorEvent(nodeId: 7,endpoint: 1,
      report: DirectColorState.fromMap(<String,int>{'hue': 90})));
    await tester.pumpAndSettle();
    pending.complete(<int,DirectColorState>{1: controller.color});
    await tester.pumpAndSettle();
    final hue = tester.widget<Slider>(find.byKey(const ValueKey('color-hue')));
    expect(hue.value, closeTo(90*360/254, 0.001));
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.events.close();
    await controller.levelEvents.close();
    await controller.colorEvents.close();
  });

  testWidgets('unknown RGB is not replaced by an invented initial color', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800,1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _ColorController()..discovery.complete(<int>[1]);
    controller.color = DirectColorState.fromMap(<String,Object?>{
      'capabilities': 1, 'mode': 0, 'hue': null, 'saturation': 254});
    await tester.pumpWidget(ManisaDirectApp(controller: controller,
      deviceStore: _RenameStore()..fail = false));
    await tester.pumpAndSettle();
    expect(find.text('رنگ فعلی دریافت نشده'), findsOneWidget);
    expect(find.byKey(const ValueKey('color-hue')), findsNothing);
    expect(find.byKey(const ValueKey('confirmed-color')), findsNothing);
    expect(controller.colorCommands, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.events.close();
    await controller.levelEvents.close();
    await controller.colorEvents.close();
  });


  testWidgets('shows only supported electrical values and marks stale data', (
    tester,
  ) async {
    final controller = _ElectricalController();
    controller.discovery.complete(<int>[1]);
    final store = _RenameStore()..fail = false;
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('مصرف برق'), findsOneWidget);
    expect(find.text('توان فعلی'), findsOneWidget);
    expect(find.text('۰ وات'), findsOneWidget);
    controller.electricalEvents.add(DirectElectricalEvent(nodeId: 7, endpoint: 1,
      report: DirectElectricalMeasurement.fromMap(<Object?, Object?>{
        'activePowerMilliwatts': 12500}), staleMetrics: const <ElectricalMetric>{}));
    await tester.pumpAndSettle();
    expect(find.text('۱۲٫۵ وات'), findsOneWidget);
    expect(find.text('۱٫۵ کیلووات‌ساعت'), findsOneWidget);
    controller.electricalEvents.add(const DirectElectricalEvent(nodeId: 7, endpoint: 1,
      staleMetrics: <ElectricalMetric>{ElectricalMetric.voltage}));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sync_problem_outlined), findsOneWidget);
    controller.electricalEvents.add(DirectElectricalEvent(nodeId: 7, endpoint: 1,
      report: DirectElectricalMeasurement.fromMap(<Object?, Object?>{
        'voltageMillivolts': 230000}), staleMetrics: const <ElectricalMetric>{}));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sync_problem_outlined), findsNothing);
    expect(find.text('۲۳۰ ولت'), findsOneWidget);
    expect(find.text('انرژی مصرف‌شده'), findsOneWidget);
    expect(find.text('۱٫۵ کیلووات‌ساعت'), findsOneWidget);
    expect(find.text('ولتاژ'), findsOneWidget);
    expect(find.text('جریان'), findsNothing);
    expect(
      store.device.measurementCapabilities[1],
      <ElectricalMetric>{
        ElectricalMetric.activePower,
        ElectricalMetric.voltage,
        ElectricalMetric.cumulativeEnergyImported,
      },
    );

    controller.failMeasurements = true;
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();
    expect(find.text('نیاز به به‌روزرسانی'), findsOneWidget);
    expect(find.text('۱۲٫۵ وات'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.events.close();
    await controller.electricalEvents.close();
  });

  testWidgets(
    'M3 features stay bound to endpoint identity across live reports and reopen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = _M3RegressionController()
        ..discovery.complete(<int>[2, 1]);
      final store = _RenameStore()
        ..fail = false
        ..device = const DirectMatterDevice(
          nodeId: 7,
          name: 'کلید اتاق کودک',
          onOffEndpoints: <int>[1, 2],
          channelNames: <int, String>{1: 'چراغ کودک', 2: 'راهرو'},
        );
      final favoriteStore = _MemoryFavoriteStore(
        catalog: const FavoriteCatalog(
          outputs: <FavoriteOutput>[
            FavoriteOutput(nodeId: 7, endpoint: 2),
          ],
        ),
      );

      Future<void> showApp() => tester.pumpWidget(
        ManisaDirectApp(
          controller: controller,
          deviceStore: store,
          favoriteStore: favoriteStore,
        ),
      );

      await showApp();
      await tester.pumpAndSettle();
      expect(store.device.onOffEndpoints, <int>[2, 1]);
      expect(find.text('علاقه‌مندی‌ها'), findsOneWidget);
      expect(find.text('راهرو'), findsWidgets);
      expect(find.text('چراغ کودک'), findsOneWidget);
      expect(find.text('رنگ نور'), findsOneWidget);
      expect(find.text('شدت نور'), findsOneWidget);
      expect(find.text('مصرف برق'), findsOneWidget);

      final rename = find.byKey(const ValueKey('rename-output-7-1'));
      await tester.ensureVisible(rename);
      await tester.tap(rename);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'خروجی ۱ اتاق کودک');
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(store.device.channelNames, <int, String>{
        1: 'خروجی ۱ اتاق کودک',
        2: 'راهرو',
      });

      controller.levelEvents.add(
        const DirectMatterLevelEvent(nodeId: 7, endpoint: 1, level: 64),
      );
      controller.colorEvents.add(
        DirectColorEvent(
          nodeId: 7,
          endpoint: 1,
          report: DirectColorState.fromMap(<String, int>{'hue': 100}),
        ),
      );
      controller.electricalEvents.add(
        DirectElectricalEvent(
          nodeId: 7,
          endpoint: 1,
          report: DirectElectricalMeasurement.fromMap(<Object?, Object?>{
            'activePowerMilliwatts': 12500,
          }),
          staleMetrics: const <ElectricalMetric>{},
        ),
      );
      controller.events.add(
        const DirectMatterOnOffEvent(
          nodeId: 7,
          endpoint: 2,
          value: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('خروجی ۱ اتاق کودک'), findsOneWidget);
      expect(find.text('راهرو'), findsWidgets);
      expect(find.text('۲۵٪'), findsOneWidget);
      expect(find.text('۱۲٫۵ وات'), findsOneWidget);
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('color-hue')))
            .value,
        closeTo(100 * 360 / 254, 0.001),
      );
      expect(favoriteStore.catalog.contains(7, 2), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await showApp();
      await tester.pumpAndSettle();
      expect(store.device.onOffEndpoints, <int>[2, 1]);
      expect(find.text('خروجی ۱ اتاق کودک'), findsOneWidget);
      expect(find.text('راهرو'), findsWidgets);
      expect(find.text('علاقه‌مندی‌ها'), findsOneWidget);
      expect(favoriteStore.catalog.contains(7, 2), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await controller.events.close();
      await controller.levelEvents.close();
      await controller.colorEvents.close();
      await controller.electricalEvents.close();
    },
  );

  testWidgets('shows a Persian dimmer only for a confirmed LevelControl endpoint', (tester) async {
    final controller = _LevelController(initialLevel: 127);
    controller.nodeValues[7] = false;
    controller.discovery.complete(<int>[1]);
    final store = _RenameStore()..fail = false;
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
    await tester.pumpAndSettle();
    expect(find.text('شدت نور'), findsOneWidget);
    expect(find.text('۵۰٪'), findsOneWidget);
    expect(store.device.levelEndpoints, <int>[1]);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(75);
    await tester.pump();
    expect(find.text('۷۵٪'), findsOneWidget);
    slider.onChangeEnd!(75);
    await tester.pumpAndSettle();
    expect(controller.levelCommands, <int>[191]);
    expect(controller.lastLevelEndpoint, 1);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    controller.levelEvents.add(
      const DirectMatterLevelEvent(nodeId: 7, endpoint: 1, level: 64),
    );
    await tester.pumpAndSettle();
    expect(find.text('۲۵٪'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.levelEvents.add(
      const DirectMatterLevelEvent(nodeId: 7, endpoint: 1, level: 254),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await controller.events.close();
    await controller.levelEvents.close();
  });

  testWidgets('nullable dimmer level is explicit and cannot send a guessed value', (tester) async {
    final controller = _LevelController(initialLevel: null);
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: _Store()));
    await tester.pumpAndSettle();
    expect(find.text('شدت نور دریافت نشده'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(controller.levelCommands, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.events.close();
    await controller.levelEvents.close();
  });

  for (final fails in <bool>[false, true]) {
    testWidgets('optional product discovery preserves controls: failure=$fails', (tester) async {
      final controller = _DescriptorController(fails: fails);
      controller.discovery.complete(<int>[1]);
      final store = _RenameStore()..fail = false;
      await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
      await tester.pumpAndSettle();
      expect(find.text(fails ? 'کنترل تک‌خروجی' : 'پریز هوشمند'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNotNull);
      toggle.onChanged!(false);
      await tester.pumpAndSettle();
      expect(controller.lastCommand, <Object>[7, 1, false]);
      expect(store.device.isSocket(1), !fails);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.events.close();
    });
  }

  testWidgets('slow descriptor does not block controls and late result is safe after dispose', (tester) async {
    final controller = _DescriptorController();
    controller.pendingTypes = Completer<Map<int, List<int>>>();
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: _Store()));
    await tester.pumpAndSettle();
    expect(find.text('کنترل تک‌خروجی'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.pendingTypes!.complete(<int, List<int>>{1: <int>[0x010a]});
    await tester.pump();
    expect(tester.takeException(), isNull);
    await controller.events.close();
  });

  testWidgets('restores live state without blocking onboarding on discovery', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _Store()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved switch'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(controller.discoveryCalls, 1);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );

    // A manual refresh may hang on an offline node, but onboarding stays usable.
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pump();
    expect(controller.discoveryCalls, 1);
    await tester.tap(find.text('افزودن وسیله'));
    await tester.pumpAndSettle();
    expect(find.text('مرحلهٔ ۱ از ۳'), findsOneWidget);
    expect(find.text('کد اتصال'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.discovery.complete(<int>[]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final succeeds in <bool>[true, false]) {
    testWidgets('removal waits for remote confirmation: $succeeds', (
      tester,
    ) async {
      final controller = _Controller();
      controller.discovery.complete(<int>[1]);
      final store = _Store();
      await tester.pumpWidget(
        ManisaDirectApp(controller: controller, deviceStore: store),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف وسیله'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'حذف وسیله'));
      await tester.pump();
      expect(store.removed, isFalse);
      expect(find.text('Saved switch'), findsOneWidget);
      if (succeeds) {
        controller.removal.complete();
      } else {
        controller.removal.completeError(
          PlatformException(code: 'matter_remove_failed'),
        );
      }
      await tester.pumpAndSettle();
      expect(store.removed, succeeds);
      expect(
        find.text('Saved switch'),
        succeeds ? findsNothing : findsOneWidget,
      );
      if (!succeeds)
        expect(find.textContaining('حذف تأیید نشد'), findsOneWidget);
    });
  }

  testWidgets('failed removal offers explicitly confirmed local deletion', (tester) async {
    final controller = _Controller()..discovery.complete(<int>[1]);
    final store = _Store();
    await tester.pumpWidget(ManisaDirectApp(controller:controller,deviceStore:store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>)); await tester.pumpAndSettle();
    await tester.tap(find.text('حذف وسیله')); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'حذف وسیله')); await tester.pump();
    controller.removal.completeError(PlatformException(code:'matter_remove_timeout'));
    await tester.pumpAndSettle();
    expect(store.removed,isFalse);
    await tester.tap(find.text('حذف از این گوشی')); await tester.pumpAndSettle();
    expect(find.text('حذف فقط از این گوشی؟'),findsOneWidget);
    expect(find.textContaining('بازنشانی کارخانه'),findsOneWidget);
    expect(store.removed,isFalse);
    await tester.tap(find.widgetWithText(FilledButton,'حذف وسیله')); await tester.pumpAndSettle();
    expect(store.removed,isTrue); expect(find.text('Saved switch'),findsNothing);
  });
  testWidgets('room metadata write failure cannot block confirmed device removal', (tester) async {
    final controller = _Controller()..discovery.complete(<int>[1]);
    final store = _Store();
    await tester.pumpWidget(ManisaDirectApp(controller:controller,deviceStore:store,roomStore:_FailRoomStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>)); await tester.pumpAndSettle();
    await tester.tap(find.text('حذف وسیله')); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'حذف وسیله')); await tester.pump();
    controller.removal.complete(); await tester.pumpAndSettle();
    expect(store.removed,isTrue); expect(find.text('Saved switch'),findsNothing);
  });

  testWidgets('discovery timeout is visible and permits retry', (tester) async {
    final controller = _Controller();
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _Store()),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.textContaining('وضعیت تازه دریافت نشد'), findsOneWidget);
    controller.discovery.complete(<int>[1]);
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();
    expect(controller.discoveryCalls, 2);
  });

  testWidgets(
    'native initialization error is shown instead of endless loading',
    (tester) async {
      await tester.pumpWidget(
        ManisaDirectApp(
          controller: _Controller(initializationFails: true),
          deviceStore: _Store(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ارتباط مانیسا راه‌اندازی نشد'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Persian onboarding validates QR before asking for Wi-Fi', (
    tester,
  ) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _Store()),
    );
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.text('خانهٔ من'))),
      TextDirection.rtl,
    );
    await tester.tap(find.text('افزودن وسیله'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();
    expect(find.textContaining('کد QR معتبر'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'MT:TEST');
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();
    expect(find.text('آماده‌کردن وسیله'), findsOneWidget);
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();
    expect(find.text('نام وای‌فای'), findsOneWidget);
    final password = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(password.obscureText, isTrue);
    expect(password.textDirection, TextDirection.ltr);
  });

  testWidgets('unknown state has no off switch', (tester) async {
    final controller = _Controller(readFails: true);
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _Store()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('وضعیت دریافت نشده'), findsOneWidget);
    expect(find.text('بررسی'), findsOneWidget);
  });

  testWidgets(
    'rename validates, preserves old name on failure and survives reload',
    (tester) async {
      final controller = _Controller();
      controller.discovery.complete(<int>[1]);
      final store = _RenameStore();
      await tester.pumpWidget(
        ManisaDirectApp(controller: controller, deviceStore: store),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تغییر نام وسیله'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(find.text('یک نام برای وسیله بنویس.'), findsOneWidget);
      expect(store.saves, 0);
      await tester.enterText(find.byType(TextField), 'کلید پذیرایی');
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(find.text('نام ذخیره نشد. دوباره تلاش کن.'), findsOneWidget);
      expect(store.device.name, 'Saved switch');
      store.fail = false;
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(find.text('کلید پذیرایی'), findsOneWidget);
      expect(store.device.nodeId, 7);
      expect(store.device.onOffEndpoints, <int>[1]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ManisaDirectApp(controller: controller, deviceStore: store),
      );
      await tester.pumpAndSettle();
      expect(find.text('کلید پذیرایی'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('output names validate and persist by endpoint', (tester) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    final store = _RenameStore()..fail = false;
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: store),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نام خروجی‌ها'));
    await tester.pumpAndSettle();
    expect(find.text('امتحان این خروجی'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('برای همهٔ خروجی‌ها نام بنویس.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'لوستر پذیرایی');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('لوستر پذیرایی'), findsOneWidget);
    expect(store.device.channelNames, <int, String>{1: 'لوستر پذیرایی'});
    expect(store.device.onOffEndpoints, <int>[1]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: store),
    );
    await tester.pumpAndSettle();
    expect(find.text('لوستر پذیرایی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline refresh preserves context and retry restores control', (
    tester,
  ) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _Store()),
    );
    await tester.pumpAndSettle();

    var control = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(control.value, isTrue);
    expect(control.onChanged, isNotNull);

    controller.readFails = true;
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();

    expect(find.text('در دسترس نیست · آخرین وضعیت: روشن'), findsOneWidget);
    expect(find.text('تلاش دوباره'), findsOneWidget);
    control = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(control.value, isTrue);
    expect(control.onChanged, isNull);

    controller.readFails = false;
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();

    expect(find.text('در دسترس نیست · آخرین وضعیت: روشن'), findsNothing);
    expect(find.text('تلاش دوباره'), findsNothing);
    control = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(control.value, isTrue);
    expect(control.onChanged, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resuming the app refreshes saved Matter state', (tester) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _Store()),
    );
    await tester.pumpAndSettle();
    final initialReads = controller.readCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(controller.readCalls, initialReads + 1);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('rapid resume events do not start concurrent node refreshes', (
    tester,
  ) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _Store()),
    );
    await tester.pumpAndSettle();
    final initialReads = controller.readCalls;
    controller.pendingRead = Completer<bool>();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.readCalls, initialReads + 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.readCalls, initialReads + 1);

    controller.pendingRead!.complete(true);
    controller.pendingRead = null;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('late event from a removed device is ignored', (tester) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _Store()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف وسیله'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حذف وسیله'));
    await tester.pump();
    controller.removal.complete();
    await tester.pumpAndSettle();
    expect(find.text('Saved switch'), findsNothing);

    controller.events.add(
      const DirectMatterOnOffEvent(nodeId: 7, endpoint: 1, value: false),
    );
    await tester.pump();

    expect(find.byType(SwitchListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed command never shows an unconfirmed state', (
    tester,
  ) async {
    final controller = _Controller()..commandFails = true;
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _Store()),
    );
    await tester.pumpAndSettle();

    final control = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(control.value, isTrue);
    control.onChanged!(false);
    await tester.pumpAndSettle();

    expect(find.textContaining('تغییر وضعیت تأیید نشد'), findsOneWidget);
    final afterFailure = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(afterFailure.value, isTrue);
    expect(afterFailure.onChanged, isNull);
  });

  testWidgets('one offline device does not block another device', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800,1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    controller.failingReadNodes.add(7);
    controller.nodeValues[8] = false;

    await tester.pumpWidget(
      ManisaDirectApp(controller: controller, deviceStore: _MultiDeviceStore()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline switch'), findsOneWidget);
    expect(find.text('Online switch'), findsOneWidget);
    expect(find.textContaining('وضعیت تازه دریافت نشد'), findsOneWidget);
    expect(controller.readCallsByNode[7], 1);
    expect(controller.readCallsByNode[8], 1);

    var controls = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(controls, hasLength(1));
    expect(controls.single.value, isFalse);
    expect(controls.single.onChanged, isNotNull);

    controller.failingReadNodes.clear();
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();

    expect(controller.readCallsByNode[7], 2);
    expect(controller.readCallsByNode[8], 1);
    controls = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(controls, hasLength(2));
    expect(controls.every((control) => control.onChanged != null), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates a room, assigns a device and restores grouping', (
    tester,
  ) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    final roomStore = _MemoryRoomStore();

    await tester.pumpWidget(
      ManisaDirectApp(
        controller: controller,
        deviceStore: _Store(),
        roomStore: roomStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('افزودن اتاق'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'پذیرایی');
    await tester.tap(find.text('ساخت اتاق'));
    await tester.pumpAndSettle();
    expect(find.text('پذیرایی'), findsOneWidget);
    expect(find.text('هنوز وسیله‌ای در این اتاق نیست'), findsOneWidget);

    await tester.tap(find.byTooltip('تنظیمات وسیله'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تغییر اتاق'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'پذیرایی'));
    await tester.pumpAndSettle();

    expect(roomStore.catalog.roomIdForDevice(7), isNotNull);
    expect(find.textContaining('۱ خروجی · پذیرایی'), findsOneWidget);
    expect(find.text('بدون اتاق'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      ManisaDirectApp(
        controller: controller,
        deviceStore: _Store(),
        roomStore: roomStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('پذیرایی'), findsOneWidget);
    expect(find.textContaining('۱ خروجی · پذیرایی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a room moves its devices to unassigned', (
    tester,
  ) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    final roomStore = _MemoryRoomStore(
      catalog: const RoomCatalog(
        rooms: <ManisaRoom>[ManisaRoom(id: 'living', name: 'پذیرایی')],
        deviceRooms: <int, String>{7: 'living'},
      ),
    );
    await tester.pumpWidget(
      ManisaDirectApp(
        controller: controller,
        deviceStore: _Store(),
        roomStore: roomStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('تنظیمات اتاق'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف اتاق'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('به بخش «بدون اتاق» منتقل می‌شود'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'حذف اتاق'));
    await tester.pumpAndSettle();

    expect(roomStore.catalog.rooms, isEmpty);
    expect(roomStore.catalog.roomIdForDevice(7), isNull);
    expect(find.text('بدون اتاق'), findsOneWidget);
    expect(find.text('Saved switch'), findsOneWidget);
  });

  testWidgets('renames the home and restores it after reopen', (tester) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    final homeStore = _MemoryHomeStore();

    await tester.pumpWidget(
      ManisaDirectApp(
        controller: controller,
        deviceStore: _Store(),
        homeStore: homeStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('خانهٔ من'), findsOneWidget);
    await tester.tap(find.byTooltip('تغییر نام خانه'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'خانهٔ پوریا');
    await tester.tap(find.widgetWithText(FilledButton, 'ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('خانهٔ پوریا'), findsOneWidget);
    expect(homeStore.profile.name, 'خانهٔ پوریا');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      ManisaDirectApp(
        controller: controller,
        deviceStore: _Store(),
        homeStore: homeStore,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('خانهٔ پوریا'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moves a room down and keeps the order after reopen', (
    tester,
  ) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    final roomStore = _MemoryRoomStore(
      catalog: const RoomCatalog(
        rooms: <ManisaRoom>[
          ManisaRoom(id: 'living', name: 'پذیرایی'),
          ManisaRoom(id: 'bedroom', name: 'اتاق خواب'),
        ],
      ),
    );

    Future<void> showApp() => tester.pumpWidget(
      ManisaDirectApp(
        controller: controller,
        deviceStore: _Store(),
        roomStore: roomStore,
      ),
    );

    await showApp();
    await tester.pumpAndSettle();
    var titles = tester
        .widgetList<Text>(find.textContaining(RegExp('پذیرایی|اتاق خواب')))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(titles.indexOf('پذیرایی'), lessThan(titles.indexOf('اتاق خواب')));

    await tester.tap(find.byTooltip('تنظیمات اتاق').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('انتقال به پایین'));
    await tester.pumpAndSettle();
    expect(roomStore.catalog.rooms.map((room) => room.id), <String>[
      'bedroom',
      'living',
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await showApp();
    await tester.pumpAndSettle();
    titles = tester
        .widgetList<Text>(find.textContaining(RegExp('پذیرایی|اتاق خواب')))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(titles.indexOf('اتاق خواب'), lessThan(titles.indexOf('پذیرایی')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds a favorite output and restores its one-tap control', (
    tester,
  ) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    final favoriteStore = _MemoryFavoriteStore();

    Future<void> showApp() => tester.pumpWidget(
      ManisaDirectApp(
        controller: controller,
        deviceStore: _Store(),
        favoriteStore: favoriteStore,
      ),
    );

    await showApp();
    await tester.pumpAndSettle();
    expect(find.text('علاقه‌مندی‌ها'), findsNothing);

    await tester.tap(find.byTooltip('افزودن به علاقه‌مندی‌ها'));
    await tester.pumpAndSettle();
    expect(find.text('علاقه‌مندی‌ها'), findsOneWidget);
    expect(find.text('۱ خروجی'), findsWidgets);
    expect(favoriteStore.catalog.contains(7, 1), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await showApp();
    await tester.pumpAndSettle();

    expect(find.text('علاقه‌مندی‌ها'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(find.byTooltip('حذف از علاقه‌مندی‌ها'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorite preserves truthful unknown state', (tester) async {
    final controller = _Controller(readFails: true);
    controller.discovery.complete(<int>[1]);
    final favoriteStore = _MemoryFavoriteStore(
      catalog: const FavoriteCatalog(
        outputs: <FavoriteOutput>[FavoriteOutput(nodeId: 7, endpoint: 1)],
      ),
    );

    await tester.pumpWidget(
      ManisaDirectApp(
        controller: controller,
        deviceStore: _Store(),
        favoriteStore: favoriteStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('علاقه‌مندی‌ها'), findsOneWidget);
    expect(find.textContaining('وضعیت دریافت نشده'), findsNWidgets(2));
    expect(find.byType(SwitchListTile), findsNothing);
  });
}

class _DescriptorController extends _Controller implements DeviceTypeReader {
  _DescriptorController({this.fails = false});
  final bool fails;
  Completer<Map<int, List<int>>>? pendingTypes;
  List<Object>? lastCommand;

  @override
  Future<Map<int, List<int>>> readDeviceTypes(int nodeId) async {
    if (fails) throw PlatformException(code: 'matter_descriptor_failed');
    return pendingTypes?.future ?? Future.value(<int, List<int>>{1: <int>[0x010a]});
  }

  @override
  Future<void> setOnOff({required int nodeId, required int endpoint, required bool value}) async {
    lastCommand = <Object>[nodeId, endpoint, value];
    nodeValues[nodeId] = value;
  }
}

class _LevelController extends _Controller
    implements DeviceTypeReader, LevelControlController, LevelEventController {
  _LevelController({required this.initialLevel});
  int? initialLevel;
  final List<int> levelCommands = <int>[];
  int? lastLevelEndpoint;
  // Each test that creates this fixture closes the stream explicitly.
  // ignore: close_sinks
  final levelEvents = StreamController<DirectMatterLevelEvent>.broadcast();

  @override
  Future<Map<int, List<int>>> readDeviceTypes(int nodeId) async => const <int, List<int>>{};

  @override
  Future<Map<int, int?>> readLevels(int nodeId) async => <int, int?>{1: initialLevel};

  @override
  Future<void> setLevel({required int nodeId, required int endpoint, required int level}) async {
    levelCommands.add(level);
    lastLevelEndpoint = endpoint;
    initialLevel = level;
    nodeValues[nodeId] = true;
  }

  @override
  Stream<DirectMatterLevelEvent> watchLevels() => levelEvents.stream;
}

class _ElectricalController extends _Controller
    implements ElectricalMeasurementController, ElectricalMeasurementEventController {
  bool failMeasurements = false;
  // Closed by the widget test that creates this fixture.
  // ignore: close_sinks
  final electricalEvents = StreamController<DirectElectricalEvent>.broadcast();

  @override
  Stream<DirectElectricalEvent> watchElectricalMeasurements() => electricalEvents.stream;

  @override
  Future<Map<int, DirectElectricalMeasurement>> readElectricalMeasurements(
    int nodeId,
  ) async {
    if (failMeasurements) {
      throw PlatformException(code: 'matter_electrical_read_failed');
    }
    return <int, DirectElectricalMeasurement>{
      1: const DirectElectricalMeasurement(
        supported: <ElectricalMetric>{
          ElectricalMetric.activePower,
          ElectricalMetric.voltage,
          ElectricalMetric.cumulativeEnergyImported,
        },
        activePowerMilliwatts: 0,
        voltageMillivolts: null,
        cumulativeEnergyImportedMilliwattHours: 1500000,
      ),
    };
  }
}

class _Controller implements DirectMatterController {
  _Controller({this.initializationFails = false, this.readFails = false});
  bool readFails;
  bool commandFails = false;
  Completer<bool>? pendingRead;
  int readCalls = 0;
  final Set<int> failingReadNodes = <int>{};
  final Map<int, bool> nodeValues = <int, bool>{};
  final Map<int, int> readCallsByNode = <int, int>{};

  final bool initializationFails;
  final discovery = Completer<List<int>>();
  final removal = Completer<void>();
  // Test fixture stream lives for the duration of its widget test.
  // ignore: close_sinks
  final events = StreamController<DirectMatterOnOffEvent>.broadcast();

  @override
  Future<void> removeDevice(int nodeId) => removal.future;
  int discoveryCalls = 0;

  @override
  Future<bool> isSupported() async {
    if (initializationFails) {
      throw PlatformException(
        code: 'matter_initialization_failed',
        message: 'Matter could not start',
      );
    }
    return true;
  }

  @override
  Stream<DirectMatterOnOffEvent> watchOnOff() => events.stream;

  @override
  Future<List<int>> discoverOnOffEndpoints(int nodeId) {
    discoveryCalls++;
    return discovery.future;
  }

  @override
  Future<bool> readOnOff({required int nodeId, required int endpoint}) async {
    readCalls++;
    readCallsByNode.update(nodeId, (value) => value + 1, ifAbsent: () => 1);
    final pending = pendingRead;
    if (pending != null) return pending.future;
    if (readFails || failingReadNodes.contains(nodeId)) {
      throw PlatformException(code: 'matter_read_failed');
    }
    return nodeValues[nodeId] ?? true;
  }

  @override
  Future<void> setOnOff({
    required int nodeId,
    required int endpoint,
    required bool value,
  }) async {
    if (commandFails) {
      throw PlatformException(code: 'matter_command_failed');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements DirectDeviceStore {
  bool removed = false;
  @override
  Future<List<DirectMatterDevice>> load() async => const <DirectMatterDevice>[
    DirectMatterDevice(
      nodeId: 7,
      name: 'Saved switch',
      onOffEndpoints: <int>[1],
    ),
  ];

  @override
  Future<void> save(DirectMatterDevice device) async {}

  @override
  Future<void> remove(int nodeId) async {
    removed = true;
  }
}

class _MultiDeviceStore implements DirectDeviceStore {
  @override
  Future<List<DirectMatterDevice>> load() async => const <DirectMatterDevice>[
    DirectMatterDevice(
      nodeId: 7,
      name: 'Offline switch',
      onOffEndpoints: <int>[1],
    ),
    DirectMatterDevice(
      nodeId: 8,
      name: 'Online switch',
      onOffEndpoints: <int>[1],
    ),
  ];

  @override
  Future<void> save(DirectMatterDevice device) async {}

  @override
  Future<void> remove(int nodeId) async {}
}

class _RenameStore implements DirectDeviceStore {
  DirectMatterDevice device = const DirectMatterDevice(
    nodeId: 7,
    name: 'Saved switch',
    onOffEndpoints: <int>[1],
  );
  bool fail = true;
  int saves = 0;
  @override
  Future<List<DirectMatterDevice>> load() async => <DirectMatterDevice>[device];
  @override
  Future<void> save(DirectMatterDevice value) async {
    saves++;
    if (fail) throw StateError('storage unavailable');
    device = value;
  }

  @override
  Future<void> remove(int nodeId) async {}
}

class _MemoryRoomStore implements RoomStore {
  _MemoryRoomStore({this.catalog = const RoomCatalog()});

  RoomCatalog catalog;

  @override
  Future<RoomCatalog> load() async => catalog;

  @override
  Future<void> save(RoomCatalog value) async {
    catalog = value;
  }
}

class _MemoryHomeStore implements HomeProfileStore {
  ManisaHomeProfile profile = const ManisaHomeProfile();

  @override
  Future<ManisaHomeProfile> load() async => profile;

  @override
  Future<void> save(ManisaHomeProfile value) async {
    profile = value;
  }
}

class _MemoryFavoriteStore implements FavoriteStore {
  _MemoryFavoriteStore({this.catalog = const FavoriteCatalog()});

  FavoriteCatalog catalog;

  @override
  Future<FavoriteCatalog> load() async => catalog;

  @override
  Future<void> save(FavoriteCatalog value) async {
    catalog = value;
  }
}

class _ColorController extends _LevelController implements ColorControlController {
  _ColorController() : super(initialLevel: 127);
  DirectColorState color = DirectColorState.fromMap(<String,int>{
    'capabilities': 1, 'mode': 0, 'hue': 169, 'saturation': 127});
  bool failColor = false;
  Completer<Map<int, DirectColorState>>? pendingColorRead;
  final colorCommands = <List<Object>>[];
  // Closed by each widget test after disposing its app.
  // ignore: close_sinks
  final colorEvents = StreamController<DirectColorEvent>.broadcast();
  @override
  Future<Map<int, DirectColorState>> readColors(int nodeId) async {
    if (failColor) throw StateError('read failed');
    if (pendingColorRead != null) return pendingColorRead!.future;
    return <int,DirectColorState>{1: color};
  }
  @override
  Future<void> setColor({required int nodeId, required int endpoint,
    required String mode, required int first, required int second}) async {
    if (failColor) throw StateError('command failed');
    colorCommands.add(<Object>[nodeId,endpoint,mode,first,second]);
    color = DirectColorState.fromMap(<String,int>{'capabilities': 1,
      'mode': 0, 'hue': 42, 'saturation': second});
  }
  @override
  Stream<DirectColorEvent> watchColors() => colorEvents.stream;
}

class _M3RegressionController extends _ColorController
    implements
        ElectricalMeasurementController,
        ElectricalMeasurementEventController {
  // Closed by the M3 cross-feature widget test.
  // ignore: close_sinks
  final electricalEvents = StreamController<DirectElectricalEvent>.broadcast();

  @override
  Stream<DirectElectricalEvent> watchElectricalMeasurements() =>
      electricalEvents.stream;

  @override
  Future<Map<int, DirectElectricalMeasurement>> readElectricalMeasurements(
    int nodeId,
  ) async => <int, DirectElectricalMeasurement>{
    1: const DirectElectricalMeasurement(
      supported: <ElectricalMetric>{
        ElectricalMetric.activePower,
        ElectricalMetric.voltage,
        ElectricalMetric.cumulativeEnergyImported,
      },
      activePowerMilliwatts: 5000,
      voltageMillivolts: 230000,
      cumulativeEnergyImportedMilliwattHours: 1500000,
    ),
  };
}

class _FailRoomStore implements RoomStore {
  @override
  Future<RoomCatalog> load() async => const RoomCatalog();
  @override
  Future<void> save(RoomCatalog value) async => throw StateError('disk');
}
