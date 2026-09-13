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

  testWidgets('offline refresh preserves context and retry restores control',
      (tester) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(ManisaDirectApp(
      controller: controller,
      deviceStore: _Store(),
    ));
    await tester.pumpAndSettle();

    var control =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(control.value, isTrue);
    expect(control.onChanged, isNotNull);

    controller.readFails = true;
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();

    expect(
      find.text('در دسترس نیست · آخرین وضعیت: روشن'),
      findsOneWidget,
    );
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
    await tester.pumpWidget(ManisaDirectApp(
      controller: controller,
      deviceStore: _Store(),
    ));
    await tester.pumpAndSettle();
    final initialReads = controller.readCalls;

    await tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(controller.readCalls, initialReads + 1);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('rapid resume events do not start concurrent node refreshes',
      (tester) async {
    final controller = _Controller();
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(ManisaDirectApp(
      controller: controller,
      deviceStore: _Store(),
    ));
    await tester.pumpAndSettle();
    final initialReads = controller.readCalls;
    controller.pendingRead = Completer<bool>();

    await tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.readCalls, initialReads + 1);

    await tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
    await tester.pumpWidget(ManisaDirectApp(
      controller: controller,
      deviceStore: _Store(),
    ));
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

    controller.events.add(const DirectMatterOnOffEvent(
      nodeId: 7,
      endpoint: 1,
      value: false,
    ));
    await tester.pump();

    expect(find.byType(SwitchListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed command never shows an unconfirmed state', (tester) async {
    final controller = _Controller()..commandFails = true;
    controller.discovery.complete(<int>[1]);
    await tester.pumpWidget(ManisaDirectApp(
      controller: controller,
      deviceStore: _Store(),
    ));
    await tester.pumpAndSettle();

    final control =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(control.value, isTrue);
    control.onChanged!(false);
    await tester.pumpAndSettle();

    expect(find.textContaining('تغییر وضعیت تأیید نشد'), findsOneWidget);
    final afterFailure =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(afterFailure.value, isTrue);
    expect(afterFailure.onChanged, isNull);
  });


}

class _Controller implements DirectMatterController {
  _Controller({this.initializationFails = false, this.readFails = false});
  bool readFails;
  bool commandFails = false;
  Completer<bool>? pendingRead;
  int readCalls = 0;

  final bool initializationFails;
  final discovery = Completer<List<int>>();
  final removal = Completer<void>();
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
    final pending = pendingRead;
    if (pending != null) return pending.future;
    if (readFails) throw PlatformException(code: 'matter_read_failed');
    return true;
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
