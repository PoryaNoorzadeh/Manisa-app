import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/design/manisa_localization.dart';
import 'package:manisa_mobile/src/matter/backlight_policy.dart';
import 'package:manisa_mobile/src/matter/backlight_screen.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/room_store.dart';

class MemoryLocale implements LocaleStore {
  String? code;
  Completer<String?>? delayed;
  bool fail = false;
  @override
  Future<String?> load() => delayed?.future ?? Future.value(code);
  @override
  Future<void> save(String value) async {
    if (fail) throw StateError('disk');
    code = value;
  }
}

class TestDevices implements DirectDeviceStore {
  @override
  Future<List<DirectMatterDevice>> load() async => [];
  @override
  Future<void> save(DirectMatterDevice device) async {}
  @override
  Future<void> remove(int nodeId) async {}
}

class TestController implements DirectMatterController {
  int starts = 0;
  @override
  Future<bool> isSupported() async {
    starts++;
    return true;
  }

  @override
  Future<List<int>> discoverOnOffEndpoints(int nodeId) async => [1];
  @override
  Future<bool> readOnOff({required int nodeId, required int endpoint}) async =>
      false;
  @override
  Future<void> setOnOff({
    required int nodeId,
    required int endpoint,
    required bool value,
  }) async {}
  @override
  Future<void> toggleOnOff({
    required int nodeId,
    required int endpoint,
  }) async {}
  @override
  Future<void> removeDevice(int nodeId) async {}
  @override
  Stream<DirectMatterOnOffEvent> watchOnOff() => const Stream.empty();
  @override
  Future<DirectMatterCommissionResult> commissionWifi({
    required String setupPayload,
    required String ssid,
    required String password,
  }) async =>
      const DirectMatterCommissionResult(nodeId: 1, onOffEndpoints: [1]);
}

class PolicyStore implements BacklightStore {
  BacklightPolicy policy = const BacklightPolicy(
    homeColor: HSVColor.fromAHSV(1, 240, 1, 1),
    endpoints: {'1:2', '2:2'},
  );
  @override
  Future<BacklightPolicy> load() async => policy;
  @override
  Future<void> save(BacklightPolicy value) async {
    policy = value;
  }
}

void main() {
  test(
    'Persian first launch, persisted languages and invalid selection',
    () async {
      final store = MemoryLocale();
      final locale = ManisaLocaleController(store);
      expect(locale.value, 'fa');
      await locale.restore();
      await locale.select('en');
      expect(store.code, 'en');
      final restored = ManisaLocaleController(store);
      await restored.restore();
      expect(restored.value, 'en');
      await restored.select('ar');
      expect(restored.value, 'ar');
      expect(() => restored.select('xx'), throwsArgumentError);
      locale.dispose();
      restored.dispose();
    },
  );
  test(
    'late restore and failed persistence do not replace a chosen language',
    () async {
      final store = MemoryLocale()..delayed = Completer<String?>();
      final locale = ManisaLocaleController(store);
      final loading = locale.restore();
      await locale.select('en');
      store.delayed!.complete('fa');
      await loading;
      expect(locale.value, 'en');
      store.fail = true;
      await expectLater(locale.select('ar'), throwsStateError);
      expect(locale.value, 'en');
      locale.dispose();
    },
  );
  test('locale copy and numeric formatting', () {
    expect(const ManisaCopy('en').text('افزودن اتاق'), 'Add room');
    expect(const ManisaCopy('ar').text('افزودن اتاق'), 'إضافة غرفة');
    expect(const ManisaCopy('fa').number('23.4'), '۲۳٫۴');
    expect(const ManisaCopy('en').number('۲۳٫۴'), '23.4');
    expect(
      ManisaCopy.translations.values.every(
        (v) => v.length == 2 && v.every((s) => s.isNotEmpty),
      ),
      isTrue,
    );
  });
  test(
    'generated copy translates counts and weekdays while preserving names',
    () {
      const copy = ManisaCopy('en');
      expect(
        copy.text(
          'اتاق «خانه ۱۲» حذف شود؟ ۲ وسیله به بخش «بدون اتاق» منتقل می‌شود.',
        ),
        'Delete room “خانه ۱۲”? 2 devices will move to No room.',
      );
      expect(
        copy.text('آخرین وضعیت: ۱ از ۲ خروجی روشن · ۱ نامشخص'),
        'Last confirmed: 1 of 2 outputs on · 1 unknown',
      );
      expect(copy.text('مرحلهٔ ۱ از ۳'), 'Step 1 of 3');
      expect(copy.text('۰۷:۰۰ · شنبه، دوشنبه'), '07:00 · Saturday, Monday');
    },
  );
  const blue = HSVColor.fromAHSV(1, 240, 1, 1),
      red = HSVColor.fromAHSV(1, 0, 1, 1),
      green = HSVColor.fromAHSV(1, 120, 1, 1);
  const devices = [
    DirectMatterDevice(
      nodeId: 1,
      name: 'Switch',
      onOffEndpoints: [1],
      colorCapabilities: {2: 1},
    ),
    DirectMatterDevice(
      nodeId: 2,
      name: 'Unselected RGB lamp',
      onOffEndpoints: [1],
      colorCapabilities: {1: 1},
    ),
    DirectMatterDevice(
      nodeId: 3,
      name: 'Bedroom switch',
      onOffEndpoints: [1],
      colorCapabilities: {2: 8},
    ),
  ];
  const rooms = RoomCatalog(
    rooms: [ManisaRoom(id: 'bed', name: 'Bedroom')],
    deviceRooms: {3: 'bed'},
  );
  test(
    'home color preserves room overrides and explicit output eligibility',
    () {
      final policy = BacklightPolicy(
        homeColor: blue,
        roomColors: {'bed': red},
        endpoints: {'1:2', '3:2'},
      ).withHomeColor(green);
      expect(policy.colorForRoom('bed'), red);
      expect(policy.colorForRoom(null), green);
      expect(policy.targets(devices, rooms).map((t) => t.key), ['1:2']);
      expect(policy.targets(devices, rooms, roomId: 'bed').map((t) => t.key), [
        '3:2',
      ]);
      expect(policy.withRoomColor('bed', null).colorForRoom('bed'), green);
      expect(
        policy.withRoomColor('bed', null).targets(devices, rooms).length,
        2,
      );
    },
  );
  test('policy persistence ignores removed or unsupported targets', () {
    final policy = BacklightPolicy(
      homeColor: blue,
      endpoints: {'1:2', '2:7', '99:2'},
    );
    final loaded = BacklightPolicy.fromJson(policy.toJson());
    expect(loaded.homeColor, blue);
    expect(loaded.endpoints, policy.endpoints);
    expect(loaded.targets(devices, rooms).map((t) => t.key), ['1:2']);
    expect(const BacklightPolicy().targets(devices, rooms), isEmpty);
  });
  test('non-finite persisted colors are rejected', () {
    expect(
      () => BacklightPolicy.fromJson({
        'home': [double.nan, 1],
        'rooms': {},
        'endpoints': [],
      }),
      throwsFormatException,
    );
  });
  testWidgets('one top add menu leads to device and room creation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ManisaDirectApp(controller: TestController(), deviceStore: TestDevices()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('افزودن'));
    await tester.pumpAndSettle();
    expect(find.text('افزودن به خانه'), findsOneWidget);
    expect(find.text('افزودن دستگاه'), findsOneWidget);
    await tester.tap(find.text('افزودن اتاق'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'language switching preserves Matter owner at 360dp and 200 percent text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = TestController();
      await tester.pumpWidget(
        ManisaDirectApp(controller: controller, deviceStore: TestDevices()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('تنظیمات').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('English'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Home name'), 150);
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.text('Home name'))),
        TextDirection.ltr,
      );
      expect(controller.starts, 1);
      await tester.scrollUntilVisible(find.text('العربية'), -150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('اسم المنزل'), 150);
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.text('اسم المنزل'))),
        TextDirection.rtl,
      );
      expect(controller.starts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'backlight sends only after apply; retries only unconfirmed outputs',
    (tester) async {
      final sent = <int>[];
      var secondWorks = false;
      final store = PolicyStore();
      await tester.pumpWidget(
        MaterialApp(
          home: BacklightScreen(
            store: store,
            rooms: () => const RoomCatalog(),
            devices: () => const [
              DirectMatterDevice(
                nodeId: 1,
                name: 'One',
                onOffEndpoints: [1],
                colorCapabilities: {2: 1},
              ),
              DirectMatterDevice(
                nodeId: 2,
                name: 'Two',
                onOffEndpoints: [1],
                colorCapabilities: {2: 1},
              ),
            ],
            apply: (target, color) async {
              sent.add(target.device.nodeId);
              return target.device.nodeId == 1 || secondWorks;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      await tester.scrollUntilVisible(find.text('اعمال رنگ'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('اعمال رنگ'));
      await tester.pumpAndSettle();
      expect(sent, [1, 2]);
      expect(find.textContaining('تأییدنشده: ۱'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(sent, [1, 2]);
      secondWorks = true;
      await tester.scrollUntilVisible(
        find.text('تلاش مجدد موارد تأییدنشده'),
        150,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('تلاش مجدد موارد تأییدنشده'));
      await tester.pumpAndSettle();
      expect(sent, [1, 2, 2]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
