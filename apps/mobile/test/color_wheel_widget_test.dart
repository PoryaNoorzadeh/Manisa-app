import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/design/color_wheel.dart';
import 'package:manisa_mobile/src/matter/backlight_policy.dart';
import 'package:manisa_mobile/src/matter/backlight_screen.dart';
import 'package:manisa_mobile/src/matter/color_control.dart';
import 'package:manisa_mobile/src/matter/color_control_widget.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/room_store.dart';

void main() {
  DirectColorState state([int hue = 0]) => DirectColorState.fromMap({
    'capabilities': 1,
    'mode': 0,
    'hue': hue,
    'saturation': 254,
  });

  testWidgets(
    'drag previews locally, sends once on release and keeps confirmed truth',
    (tester) async {
      final sent = <HSVColor>[];
      var confirmed = state();
      var busy = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                rebuild = update;
                return ColorControl(
                  state: confirmed,
                  enabled: true,
                  stale: false,
                  busy: busy,
                  onChanged: sent.add,
                  onRefresh: () {},
                );
              },
            ),
          ),
        ),
      );
      final wheel = find.byType(ColorWheel);
      final rect = tester.getRect(wheel);
      final gesture = await tester.startGesture(rect.center);
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.moveTo(rect.center + const Offset(60, 60));
      await tester.pump();
      expect(sent, isEmpty);
      final draft = tester.widget<ColorWheel>(wheel).value;
      expect(draft.hue, closeTo(45, 1));
      expect(draft.saturation, inExclusiveRange(0, 1));
      final actual = tester.widget<Container>(
        find.byKey(const ValueKey('confirmed-color')),
      );
      expect(
        (actual.decoration! as BoxDecoration).color,
        const Color(0xffff0000),
      );
      expect(find.byKey(const ValueKey('color-preview')), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(sent, hasLength(1));
      expect(sent.single, draft);
      rebuild(() => busy = true);
      await tester.pump();
      expect(tester.widget<ColorWheel>(wheel).value, draft);
      rebuild(() => confirmed = state(40));
      await tester.pump();
      expect(tester.widget<ColorWheel>(wheel).value, draft);
      rebuild(() => busy = false);
      await tester.pump();
      expect(find.byKey(const ValueKey('color-preview')), findsNothing);
      expect(tester.widget<ColorWheel>(wheel).value, confirmed.hsv);
    },
  );

  testWidgets(
    'center selects white; rim clamps saturation and supports repeated busy edits',
    (tester) async {
      final sent = <HSVColor>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorControl(
              state: state(),
              enabled: true,
              busy: true,
              stale: false,
              onChanged: sent.add,
              onRefresh: () {},
            ),
          ),
        ),
      );
      final wheel = find.byType(ColorWheel);
      final rect = tester.getRect(wheel);
      await tester.tapAt(rect.center);
      await tester.pump();
      expect(sent.single.saturation, 0);
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(rect.center + const Offset(190, 0));
      await tester.pump();
      expect(sent, hasLength(1));
      await gesture.up();
      await tester.pump();
      expect(sent, hasLength(2));
      expect(sent.last.saturation, 1);
      expect(sent.last.hue, 0);
    },
  );

  testWidgets('cancelled drag restores confirmed color without a command', (
    tester,
  ) async {
    final sent = <HSVColor>[];
    final confirmed = state();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorControl(
            state: confirmed,
            enabled: true,
            stale: false,
            onChanged: sent.add,
            onRefresh: () {},
          ),
        ),
      ),
    );
    final wheel = find.byType(ColorWheel);
    final gesture = await tester.startGesture(tester.getCenter(wheel));
    await gesture.moveBy(const Offset(50, 50));
    await tester.pump();
    expect(find.byKey(const ValueKey('color-preview')), findsOneWidget);
    await gesture.cancel();
    await tester.pump();
    expect(sent, isEmpty);
    expect(find.byKey(const ValueKey('color-preview')), findsNothing);
    expect(tester.widget<ColorWheel>(wheel).value, confirmed.hsv);
  });

  testWidgets('stale and disabled controls cannot send', (tester) async {
    final sent = <HSVColor>[];
    for (final stale in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorControl(
              state: state(),
              enabled: stale,
              stale: stale,
              onChanged: sent.add,
              onRefresh: () {},
            ),
          ),
        ),
      );
      await tester.tapAt(tester.getCenter(find.byType(ColorWheel)));
      await tester.pump();
      expect(sent, isEmpty);
    }
  });

  testWidgets('physical wheel coordinates are identical in RTL and LTR', (
    tester,
  ) async {
    final selections = <HSVColor>[];
    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Center(
              child: ColorWheel(
                value: const HSVColor.fromAHSV(1, 0, 1, 1),
                semanticLabel: 'Color',
                onChanged: (_) {},
                onChangeEnd: selections.add,
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(ColorWheel));
      await tester.tapAt(rect.center + const Offset(0, 60));
      await tester.pump();
    }
    expect(selections, hasLength(2));
    expect(selections.first, selections.last);
    expect(selections.first.hue, 90);
  });

  testWidgets('backlight wheel stays local until explicit Apply', (
    tester,
  ) async {
    var applies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BacklightScreen(
          store: _BacklightTestStore(),
          devices: () => [
            const DirectMatterDevice(
              nodeId: 7,
              name: 'Switch',
              onOffEndpoints: [1],
              colorCapabilities: {1: 1},
            ),
          ],
          rooms: () => const RoomCatalog(),
          apply: (_, _) async {
            applies++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final wheel = find.byType(ColorWheel);
    await tester.ensureVisible(wheel);
    final gesture = await tester.startGesture(tester.getCenter(wheel));
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(applies, 0);
    expect(
      tester.widget<ColorWheel>(wheel).value.saturation,
      inExclusiveRange(0, 1),
    );
    expect(find.byType(Slider), findsNothing);
    final apply = find.widgetWithText(FilledButton, 'اعمال رنگ');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(applies, 1);
  });
}

class _BacklightTestStore implements BacklightStore {
  @override
  Future<BacklightPolicy> load() async =>
      const BacklightPolicy(endpoints: {'7:1'});
  @override
  Future<void> save(BacklightPolicy policy) async {}
}
