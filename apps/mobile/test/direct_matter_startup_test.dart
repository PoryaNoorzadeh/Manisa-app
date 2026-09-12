import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';

void main() {
  testWidgets('restores live state without blocking onboarding on discovery',
      (tester) async {
    final controller = _Controller();
    await tester.pumpWidget(ManisaDirectApp(
      controller: controller,
      deviceStore: _Store(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saved switch'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(controller.discoveryCalls, 1);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

    // A manual refresh may hang on an offline node, but onboarding stays usable.
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pump();
    expect(controller.discoveryCalls, 1);
    await tester.tap(find.text('افزودن وسیله'));
    await tester.pumpAndSettle();
    expect(find.text('کد اتصال'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.discovery.complete(<int>[]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final succeeds in <bool>[true, false]) {
    testWidgets('removal waits for remote confirmation: $succeeds', (tester) async {
      final controller = _Controller();
      controller.discovery.complete(<int>[1]);
      final store = _Store();
      await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
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
        controller.removal.completeError(PlatformException(code: 'matter_remove_failed'));
      }
      await tester.pumpAndSettle();
      expect(store.removed, succeeds);
      expect(find.text('Saved switch'), succeeds ? findsNothing : findsOneWidget);
      if (!succeeds) expect(find.textContaining('حذف تأیید نشد'), findsOneWidget);
    });
  }

  testWidgets('discovery timeout is visible and permits retry', (tester) async {
    final controller = _Controller();
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: _Store()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.textContaining('وضعیت تازه دریافت نشد'), findsOneWidget);
    controller.discovery.complete(<int>[1]);
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();
    expect(controller.discoveryCalls, 2);
  });

  testWidgets('native initialization error is shown instead of endless loading',
      (tester) async {
    await tester.pumpWidget(ManisaDirectApp(
      controller: _Controller(initializationFails: true),
      deviceStore: _Store(),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('ارتباط مانیسا راه‌اندازی نشد'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Persian onboarding validates QR before asking for Wi-Fi', (tester) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: _Store()));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.text('خانهٔ من'))), TextDirection.rtl);
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
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: _Store()));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('وضعیت دریافت نشده'), findsOneWidget);
    expect(find.text('بررسی'), findsOneWidget);
  });

  testWidgets('rename validates, preserves old name on failure and survives reload', (tester) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    final store = _RenameStore();
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
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
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
    await tester.pumpAndSettle();
    expect(find.text('کلید پذیرایی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('output names validate and persist by endpoint', (tester) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    final store = _RenameStore()..fail = false;
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
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
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
    await tester.pumpAndSettle();
    expect(find.text('لوستر پذیرایی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}

class _Controller implements DirectMatterController {
  _Controller({this.initializationFails = false, this.readFails = false});
  final bool readFails;

  final bool initializationFails;
  final discovery = Completer<List<int>>();
  final removal = Completer<void>();

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
  Stream<DirectMatterOnOffEvent> watchOnOff() => const Stream.empty();

  @override
  Future<List<int>> discoverOnOffEndpoints(int nodeId) {
    discoveryCalls++;
    return discovery.future;
  }

  @override
  Future<bool> readOnOff({required int nodeId, required int endpoint}) async {
    if (readFails) throw PlatformException(code: 'matter_read_failed');
    return true;
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
  Future<void> remove(int nodeId) async { removed = true; }
}

class _RenameStore implements DirectDeviceStore {
  DirectMatterDevice device = const DirectMatterDevice(
    nodeId: 7, name: 'Saved switch', onOffEndpoints: <int>[1]);
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
