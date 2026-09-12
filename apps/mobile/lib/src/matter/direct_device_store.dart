import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class DirectMatterDevice {
  const DirectMatterDevice({
    required this.nodeId,
    required this.name,
    required this.onOffEndpoints,
  });

  final int nodeId;
  final String name;
  final List<int> onOffEndpoints;

  DirectMatterDevice copyWith({String? name, List<int>? onOffEndpoints}) =>
      DirectMatterDevice(
        nodeId: nodeId,
        name: name ?? this.name,
        onOffEndpoints: onOffEndpoints ?? this.onOffEndpoints,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'nodeId': nodeId,
        'name': name,
        'onOffEndpoints': onOffEndpoints,
      };

  factory DirectMatterDevice.fromJson(Map<String, Object?> json) {
    final nodeId = json['nodeId'];
    final name = json['name'];
    final endpoints = json['onOffEndpoints'];
    if (nodeId is! int || name is! String || endpoints is! List<Object?>) {
      throw const FormatException('invalid direct Matter device');
    }
    return DirectMatterDevice(
      nodeId: nodeId,
      name: name,
      onOffEndpoints: endpoints.map((value) {
        if (value is! int) {
          throw const FormatException('invalid direct Matter endpoint');
        }
        return value;
      }).toList(growable: false),
    );
  }
}

abstract interface class DirectDeviceStore {
  Future<List<DirectMatterDevice>> load();
  Future<void> save(DirectMatterDevice device);
  Future<void> remove(int nodeId);
}

final class PreferencesDirectDeviceStore implements DirectDeviceStore {
  PreferencesDirectDeviceStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _key = 'manisa_direct_matter_devices_v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<DirectMatterDevice>> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const <DirectMatterDevice>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) {
        return const <DirectMatterDevice>[];
      }
      return decoded
          .whereType<Map<String, Object?>>()
          .map(DirectMatterDevice.fromJson)
          .toList(growable: false);
    } on FormatException {
      return const <DirectMatterDevice>[];
    }
  }

  @override
  Future<void> save(DirectMatterDevice device) async {
    final devices = <DirectMatterDevice>[
      ...await load().then(
        (items) => items.where((item) => item.nodeId != device.nodeId),
      ),
      device,
    ]..sort((a, b) => a.nodeId.compareTo(b.nodeId));
    await _write(devices);
  }

  @override
  Future<void> remove(int nodeId) async {
    final devices = (await load())
        .where((device) => device.nodeId != nodeId)
        .toList(growable: false);
    await _write(devices);
  }

  Future<void> _write(List<DirectMatterDevice> devices) =>
      _preferences.setString(
        _key,
        jsonEncode(devices.map((device) => device.toJson()).toList()),
      );
}
