import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class SceneAction {
  const SceneAction({required this.nodeId, required this.endpoint, required this.on});
  final int nodeId;
  final int endpoint;
  final bool on;
  String get key => '$nodeId:$endpoint';
  Map<String, Object?> toJson() => <String, Object?>{'nodeId':nodeId,'endpoint':endpoint,'on':on};
  factory SceneAction.fromJson(Map<String,Object?> json) {
    final node = json['nodeId']; final endpoint = json['endpoint']; final on = json['on'];
    if (node is! int || node <= 0 || endpoint is! int || endpoint < 1 || endpoint > 65534 || on is! bool) {
      throw const FormatException('invalid scene action');
    }
    return SceneAction(nodeId:node,endpoint:endpoint,on:on);
  }
}
final class ManualScene {
  ManualScene({required this.id, required String name, required List<SceneAction> actions})
      : name = name.trim(), actions = List<SceneAction>.unmodifiable(actions) {
    if (id.isEmpty || this.name.isEmpty || this.name.length > 60 || actions.isEmpty ||
        actions.length > 32 || actions.map((a) => a.key).toSet().length != actions.length) {
      throw const FormatException('invalid manual scene');
    }
    for (final action in actions) { SceneAction.fromJson(action.toJson()); }
  }
  final String id;
  final String name;
  final List<SceneAction> actions;
  Map<String,Object?> toJson() => <String,Object?>{'id':id,'name':name,'actions':actions.map((a)=>a.toJson()).toList()};
  factory ManualScene.fromJson(Map<String,Object?> json) {
    if (json['id'] is! String || json['name'] is! String || json['actions'] is! List<Object?>) {
      throw const FormatException('invalid manual scene');
    }
    return ManualScene(id:json['id']! as String,name:json['name']! as String,
      actions:(json['actions']! as List<Object?>).map((a) {
        if (a is! Map<String,Object?>) throw const FormatException('invalid scene action');
        return SceneAction.fromJson(a);
      }).toList());
  }
}
abstract interface class SceneStore {
  Future<List<ManualScene>> load();
  Future<void> save(List<ManualScene> scenes);
}
final class PreferencesSceneStore implements SceneStore {
  PreferencesSceneStore({SharedPreferencesAsync? preferences}) : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  static const key = 'manisa_manual_scenes_v1';
  @override
  Future<List<ManualScene>> load() async {
    final raw = await _preferences.getString(key);
    if (raw == null) return <ManualScene>[];
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String,Object?> || decoded['version'] != 1 || decoded['scenes'] is! List<Object?>) {
      throw const FormatException('invalid scene catalog');
    }
    final scenes = (decoded['scenes']! as List<Object?>).map((s) {
      if (s is! Map<String,Object?>) throw const FormatException('invalid scene');
      return ManualScene.fromJson(s);
    }).toList();
    if (scenes.map((s)=>s.id).toSet().length != scenes.length) throw const FormatException('duplicate scene id');
    return scenes;
  }
  @override
  Future<void> save(List<ManualScene> scenes) => _preferences.setString(key,
    jsonEncode(<String,Object?>{'version':1,'scenes':scenes.map((s)=>s.toJson()).toList()}));
}
class MemorySceneStore implements SceneStore {
  List<ManualScene> scenes = <ManualScene>[];
  @override
  Future<List<ManualScene>> load() async => List<ManualScene>.of(scenes);
  @override
  Future<void> save(List<ManualScene> value) async { scenes = List<ManualScene>.of(value); }
}

enum SceneActionStatus { confirmed, failed, unknown, unavailable }

/// Explicit On/Off is idempotent. No toggles, automatic retries, persisted runs
/// or command replay on restart. A timeout is unknown, never assumed failure.
final class SceneRunner {
  bool _running = false;
  bool _cancelled = false;
  bool get running => _running;
  void cancel() { _cancelled = true; }
  Future<Map<String,SceneActionStatus>> run(ManualScene scene, {
    required bool Function(SceneAction) available,
    required Future<bool> Function(SceneAction) execute,
    Set<String>? only,
    Duration timeout = const Duration(seconds: 32),
  }) async {
    if (_running) throw StateError('scene already running');
    _running = true; _cancelled = false;
    final result = <String,SceneActionStatus>{};
    try {
      for (final action in scene.actions) {
        if (only != null && !only.contains(action.key)) continue;
        if (_cancelled || !available(action)) {
          result[action.key] = SceneActionStatus.unavailable;
          continue;
        }
        try {
          final confirmed = await execute(action).timeout(timeout);
          result[action.key] = confirmed ? SceneActionStatus.confirmed : SceneActionStatus.failed;
        } on TimeoutException {
          result[action.key] = SceneActionStatus.unknown;
        } catch (_) {
          result[action.key] = SceneActionStatus.failed;
        }
      }
      return result;
    } finally { _running = false; }
  }
}
