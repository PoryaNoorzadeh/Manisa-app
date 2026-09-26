import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class SceneAutomation {
  SceneAutomation({
    required this.id,
    required this.sceneId,
    required this.hour,
    required this.minute,
    required Set<int> weekdays,
    this.enabled = true,
    this.lastHandledSlot,
  }) : weekdays = Set<int>.unmodifiable(weekdays) {
    if (id.isEmpty ||
        sceneId.isEmpty ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        weekdays.isEmpty ||
        weekdays.any((day) => day < DateTime.monday || day > DateTime.sunday)) {
      throw const FormatException('invalid scene automation');
    }
  }

  final String id;
  final String sceneId;
  final int hour;
  final int minute;
  final Set<int> weekdays;
  final bool enabled;
  final String? lastHandledSlot;

  String slotFor(DateTime localDay) =>
      '${localDay.year.toString().padLeft(4, '0')}-'
      '${localDay.month.toString().padLeft(2, '0')}-'
      '${localDay.day.toString().padLeft(2, '0')}@$hour:$minute';

  DateTime scheduledOn(DateTime localDay) => DateTime(
    localDay.year,
    localDay.month,
    localDay.day,
    hour,
    minute,
  );

  SceneAutomation copyWith({
    String? sceneId,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    bool? enabled,
    String? lastHandledSlot,
    bool clearLastHandledSlot = false,
  }) => SceneAutomation(
    id: id,
    sceneId: sceneId ?? this.sceneId,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weekdays: weekdays ?? this.weekdays,
    enabled: enabled ?? this.enabled,
    lastHandledSlot: clearLastHandledSlot
        ? null
        : lastHandledSlot ?? this.lastHandledSlot,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sceneId': sceneId,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays.toList()..sort(),
    'enabled': enabled,
    if (lastHandledSlot != null) 'lastHandledSlot': lastHandledSlot,
  };

  factory SceneAutomation.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final sceneId = json['sceneId'];
    final hour = json['hour'];
    final minute = json['minute'];
    final weekdays = json['weekdays'];
    final enabled = json['enabled'];
    final lastHandledSlot = json['lastHandledSlot'];
    if (id is! String ||
        sceneId is! String ||
        hour is! int ||
        minute is! int ||
        weekdays is! List<Object?> ||
        weekdays.any((day) => day is! int) ||
        enabled is! bool ||
        (lastHandledSlot != null && lastHandledSlot is! String)) {
      throw const FormatException('invalid scene automation');
    }
    return SceneAutomation(
      id: id,
      sceneId: sceneId,
      hour: hour,
      minute: minute,
      weekdays: weekdays.cast<int>().toSet(),
      enabled: enabled,
      lastHandledSlot: lastHandledSlot as String?,
    );
  }
}

final class AutomationClaim {
  const AutomationClaim({required this.automation, required this.shouldRun});

  final SceneAutomation automation;
  final bool shouldRun;
}

/// Claims today's due slot before any command is sent. This gives local
/// automations at-most-once restart semantics. Slots older than [grace] are
/// handled without replaying device commands.
List<AutomationClaim> claimDueAutomations(
  List<SceneAutomation> automations,
  DateTime now, {
  Duration grace = const Duration(minutes: 10),
}) {
  final claims = <AutomationClaim>[];
  for (final automation in automations) {
    if (!automation.enabled || !automation.weekdays.contains(now.weekday)) {
      continue;
    }
    final scheduled = automation.scheduledOn(now);
    if (now.isBefore(scheduled)) continue;
    final slot = automation.slotFor(now);
    if (automation.lastHandledSlot == slot) continue;
    claims.add(
      AutomationClaim(
        automation: automation.copyWith(lastHandledSlot: slot),
        shouldRun: now.difference(scheduled) <= grace,
      ),
    );
  }
  return claims;
}

abstract interface class AutomationStore {
  Future<List<SceneAutomation>> load();

  Future<List<SceneAutomation>> mutate(
    List<SceneAutomation> Function(List<SceneAutomation>) update,
  );
}

final class PreferencesAutomationStore implements AutomationStore {
  PreferencesAutomationStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const key = 'manisa_scene_automations_v1';
  final SharedPreferencesAsync _preferences;
  Future<void> _tail = Future<void>.value();

  Future<List<SceneAutomation>> _load() async {
    final raw = await _preferences.getString(key);
    if (raw == null) return <SceneAutomation>[];
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?> ||
        decoded['version'] != 1 ||
        decoded['automations'] is! List<Object?>) {
      throw const FormatException('invalid automation catalog');
    }
    final result = (decoded['automations']! as List<Object?>).map((value) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('invalid automation');
      }
      return SceneAutomation.fromJson(value);
    }).toList(growable: false);
    if (result.map((item) => item.id).toSet().length != result.length) {
      throw const FormatException('duplicate automation id');
    }
    return result;
  }

  @override
  Future<List<SceneAutomation>> load() {
    final completer = Completer<List<SceneAutomation>>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await _load());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  @override
  Future<List<SceneAutomation>> mutate(
    List<SceneAutomation> Function(List<SceneAutomation>) update,
  ) {
    final completer = Completer<List<SceneAutomation>>();
    _tail = _tail.then((_) async {
      try {
        final next = List<SceneAutomation>.unmodifiable(update(await _load()));
        if (next.map((item) => item.id).toSet().length != next.length) {
          throw const FormatException('duplicate automation id');
        }
        await _preferences.setString(
          key,
          jsonEncode(<String, Object?>{
            'version': 1,
            'automations': next.map((item) => item.toJson()).toList(),
          }),
        );
        completer.complete(next);
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}

final class MemoryAutomationStore implements AutomationStore {
  MemoryAutomationStore([List<SceneAutomation> initial = const <SceneAutomation>[]])
    : automations = List<SceneAutomation>.of(initial);

  List<SceneAutomation> automations;

  @override
  Future<List<SceneAutomation>> load() async =>
      List<SceneAutomation>.of(automations);

  @override
  Future<List<SceneAutomation>> mutate(
    List<SceneAutomation> Function(List<SceneAutomation>) update,
  ) async {
    automations = List<SceneAutomation>.of(update(await load()));
    return load();
  }
}
