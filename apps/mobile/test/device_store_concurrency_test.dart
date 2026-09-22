import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesState {
  String? raw;
  Completer<String?>? pause;
  int reads = 0;
  bool failWrite = false;
}
class PausedPreferences implements SharedPreferencesAsync {
  final _state = PreferencesState();
  String? get raw => _state.raw;
  set raw(String? value) => _state.raw = value;
  Completer<String?>? get pause => _state.pause;
  set pause(Completer<String?>? value) => _state.pause = value;
  int get reads => _state.reads;
  set reads(int value) => _state.reads = value;
  bool get failWrite => _state.failWrite;
  set failWrite(bool value) => _state.failWrite = value;
  @override
  Future<String?> getString(String key) async {
    reads++;
    final pending = pause;
    pause = null;
    return pending == null ? raw : pending.future;
  }
  @override
  Future<void> setString(String key, String value) async {
    if (failWrite) { failWrite = false; throw StateError('disk'); }
    raw = value;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
const first = DirectMatterDevice(nodeId:7,name:'اول',onOffEndpoints:<int>[1]);
const second = DirectMatterDevice(nodeId:8,name:'دوم',onOffEndpoints:<int>[1]);
void main() {
  test('concurrent metadata save cannot resurrect a removed device', () async {
    final preferences = PausedPreferences()..raw=jsonEncode(<Object?>[first.toJson()]);
    final store = PreferencesDirectDeviceStore(preferences:preferences);
    final oldList=preferences.raw;
    final barrier=Completer<String?>(); preferences.pause=barrier;
    final updating=store.save(second);
    await Future<void>.delayed(Duration.zero);
    final removing=store.remove(7);
    await Future<void>.delayed(Duration.zero);
    expect(preferences.reads,1);
    barrier.complete(oldList);
    await Future.wait(<Future<void>>[updating,removing]);
    expect((await store.load()).map((d)=>d.nodeId),<int>[8]);
  });
  test('failed write does not poison later deletion or saves', () async {
    final preferences=PausedPreferences()..raw=jsonEncode(<Object?>[first.toJson()])..failWrite=true;
    final store=PreferencesDirectDeviceStore(preferences:preferences);
    await expectLater(store.save(second),throwsStateError);
    await store.remove(7);
    expect(await store.load(),isEmpty);
    await store.save(second);
    expect((await store.load()).single.nodeId,8);
  });
}
