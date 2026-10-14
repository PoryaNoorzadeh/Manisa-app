import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/scene_automation.dart';

SceneAutomation automation({
  bool enabled = true,
  String? lastHandledSlot,
  Set<int> weekdays = const <int>{DateTime.monday},
}) =>
    SceneAutomation(
      id: 'morning',
      sceneId: 'lights-on',
      hour: 8,
      minute: 30,
      weekdays: weekdays,
      enabled: enabled,
      lastHandledSlot: lastHandledSlot,
    );

void main() {
  test('automation JSON preserves schedule and validates corrupt values', () {
    final original = automation(lastHandledSlot: '2026-09-28@8:30');
    final restored = SceneAutomation.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
    );

    expect(restored.sceneId, 'lights-on');
    expect(restored.weekdays, <int>{DateTime.monday});
    expect(restored.lastHandledSlot, '2026-09-28@8:30');
    expect(
      () => SceneAutomation(
        id: 'bad',
        sceneId: 'scene',
        hour: 24,
        minute: 0,
        weekdays: const <int>{DateTime.monday},
      ),
      throwsFormatException,
    );
  });

  test('due slot is claimed once and runs only inside ten-minute grace', () {
    final due = DateTime(2026, 9, 28, 8, 35); // Monday.
    final first = claimDueAutomations(<SceneAutomation>[automation()], due);

    expect(first, hasLength(1));
    expect(first.single.shouldRun, isTrue);
    expect(first.single.automation.lastHandledSlot, '2026-09-28@8:30');
    expect(
      claimDueAutomations(<SceneAutomation>[first.single.automation], due),
      isEmpty,
    );

    final late = claimDueAutomations(
      <SceneAutomation>[automation()],
      DateTime(2026, 9, 28, 8, 41),
    );
    expect(late.single.shouldRun, isFalse);
    expect(late.single.automation.lastHandledSlot, '2026-09-28@8:30');
  });

  test('future, disabled and wrong-weekday schedules are not claimed', () {
    expect(
      claimDueAutomations(
        <SceneAutomation>[automation()],
        DateTime(2026, 9, 28, 8, 29),
      ),
      isEmpty,
    );
    expect(
      claimDueAutomations(
        <SceneAutomation>[automation(enabled: false)],
        DateTime(2026, 9, 28, 8, 35),
      ),
      isEmpty,
    );
    expect(
      claimDueAutomations(
        <SceneAutomation>[automation()],
        DateTime(2026, 9, 29, 8, 35),
      ),
      isEmpty,
    );
  });

  test('memory store mutation persists the claimed slot', () async {
    final store = MemoryAutomationStore(<SceneAutomation>[automation()]);
    final saved = await store.mutate((current) => <SceneAutomation>[
      claimDueAutomations(
        current,
        DateTime(2026, 9, 28, 8, 35),
      ).single.automation,
    ]);

    expect(saved.single.lastHandledSlot, '2026-09-28@8:30');
    expect((await store.load()).single.lastHandledSlot, '2026-09-28@8:30');
  });
}
