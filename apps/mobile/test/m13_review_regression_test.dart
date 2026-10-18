import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/design/manisa_localization.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/manual_scene.dart';
import 'package:manisa_mobile/src/matter/manual_scene_screen.dart';
import 'package:manisa_mobile/src/matter/room_store.dart';

import 'm13_design_test.dart' show TestController, TestDevices, MemoryLocale;

class NamedDevices extends TestDevices {
  @override
  Future<List<DirectMatterDevice>> load() async => const [
    DirectMatterDevice(nodeId: 1, name: 'Device', onOffEndpoints: [1]),
  ];
}

class Rooms implements RoomStore {
  RoomCatalog value = const RoomCatalog(
    rooms: [ManisaRoom(id: 'bed', name: 'خانه')],
    deviceRooms: {1: 'bed'},
  );
  @override
  Future<RoomCatalog> load() async => value;
  @override
  Future<void> save(RoomCatalog catalog) async {
    value = catalog;
  }
}

class Scenes implements SceneStore {
  @override
  Future<List<ManualScene>> load() async => [
    ManualScene(
      id: 'one',
      name: 'خاموش',
      actions: const [SceneAction(nodeId: 1, endpoint: 1, on: false)],
    ),
  ];
  @override
  Future<void> save(List<ManualScene> scenes) async {}
}

void main() {
  testWidgets(
    'deleting selected room restores all devices without another filter tap',
    (tester) async {
      final rooms = Rooms();
      await tester.pumpWidget(
        ManisaDirectApp(
          controller: TestController(),
          deviceStore: NamedDevices(),
          roomStore: rooms,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'خانه'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('تنظیمات اتاق'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف اتاق'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'حذف اتاق'));
      await tester.pumpAndSettle();
      expect(rooms.value.rooms, isEmpty);
      expect(find.text('Device'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'room title is user content even when its name matches translated copy',
    (tester) async {
      await tester.pumpWidget(
        ManisaDirectApp(
          controller: TestController(),
          deviceStore: NamedDevices(),
          roomStore: Rooms(),
          localeStore: MemoryLocale()..code = 'en',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('خانه'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('scene name is never translated in English', (tester) async {
    final locale = ManisaLocaleController(MemoryLocale())..value = 'en';
    await tester.pumpWidget(
      ManisaLocaleScope(
        controller: locale,
        child: MaterialApp(
          locale: const Locale('en'),
          home: ManualSceneScreen(
            store: Scenes(),
            devices: () => const [
              DirectMatterDevice(
                nodeId: 1,
                name: 'Device',
                onOffEndpoints: [1],
              ),
            ],
            execute: (_) async => true,
            runner: SceneRunner(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('خاموش'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    locale.dispose();
  });
}
