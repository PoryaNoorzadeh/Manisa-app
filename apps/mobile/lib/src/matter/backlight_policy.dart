import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'direct_device_store.dart';
import 'room_store.dart';

final class BacklightTarget {
  const BacklightTarget(this.device, this.endpoint);
  final DirectMatterDevice device;
  final int endpoint;
  String get key => '${device.nodeId}:$endpoint';
}

/// Intent, not observed state. Only an explicit Apply action sends commands.
final class BacklightPolicy {
  const BacklightPolicy({
    this.homeColor,
    this.roomColors = const {},
    this.endpoints = const {},
  });
  final HSVColor? homeColor;
  final Map<String, HSVColor> roomColors;
  final Set<String> endpoints;
  HSVColor? colorForRoom(String? roomId) => roomColors[roomId] ?? homeColor;
  BacklightPolicy withHomeColor(HSVColor color) => BacklightPolicy(
    homeColor: color,
    roomColors: roomColors,
    endpoints: endpoints,
  );
  BacklightPolicy withRoomColor(String id, HSVColor? color) => BacklightPolicy(
    homeColor: homeColor,
    roomColors: {
      for (final entry in roomColors.entries)
        if (entry.key != id) entry.key: entry.value,
      if (color != null) id: color,
    },
    endpoints: endpoints,
  );
  BacklightPolicy withEndpoints(Set<String> selected) => BacklightPolicy(
    homeColor: homeColor,
    roomColors: roomColors,
    endpoints: Set.unmodifiable(selected),
  );
  List<BacklightTarget> targets(
    List<DirectMatterDevice> devices,
    RoomCatalog rooms, {
    String? roomId,
  }) => [
    for (final device in devices)
      if (roomId != null
          ? rooms.roomIdForDevice(device.nodeId) == roomId
          : !roomColors.containsKey(rooms.roomIdForDevice(device.nodeId)))
        for (final capability in device.colorCapabilities.entries)
          if (capability.value & 9 != 0 &&
              endpoints.contains('${device.nodeId}:${capability.key}'))
            BacklightTarget(device, capability.key),
  ];
  Map<String, Object?> toJson() => {
    'version': 1,
    'home': homeColor == null ? null : [homeColor!.hue, homeColor!.saturation],
    'rooms': roomColors.map(
      (key, color) => MapEntry(key, [color.hue, color.saturation]),
    ),
    'endpoints': endpoints.toList(),
  };
  factory BacklightPolicy.fromJson(Map<String, Object?> json) {
    HSVColor decode(Object? value) {
      if (value is! List ||
          value.length != 2 ||
          value.any((v) => v is! num || !v.isFinite))
        throw const FormatException('invalid backlight color');
      final hue = (value[0] as num).toDouble(),
          saturation = (value[1] as num).toDouble();
      if (hue < 0 || hue >= 360 || saturation < 0 || saturation > 1)
        throw const FormatException('invalid backlight range');
      return HSVColor.fromAHSV(1, hue, saturation, 1);
    }

    final rawRooms = json['rooms'], rawEndpoints = json['endpoints'];
    if (rawRooms is! Map<String, Object?> ||
        rawEndpoints is! List ||
        rawEndpoints.any(
          (v) =>
              v is! String || !RegExp(r'^[1-9][0-9]*:[1-9][0-9]*$').hasMatch(v),
        ))
      throw const FormatException('invalid backlight policy');
    return BacklightPolicy(
      homeColor: json['home'] == null ? null : decode(json['home']),
      roomColors: Map.unmodifiable(
        rawRooms.map((key, value) => MapEntry(key, decode(value))),
      ),
      endpoints: Set.unmodifiable(rawEndpoints.cast<String>()),
    );
  }
}

abstract interface class BacklightStore {
  Future<BacklightPolicy> load();
  Future<void> save(BacklightPolicy policy);
}

class EmptyBacklightStore implements BacklightStore {
  const EmptyBacklightStore();
  @override
  Future<BacklightPolicy> load() async => const BacklightPolicy();
  @override
  Future<void> save(BacklightPolicy policy) async {}
}

class PreferencesBacklightStore implements BacklightStore {
  PreferencesBacklightStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  static const key = 'manisa_backlight_policy_v1';
  @override
  Future<BacklightPolicy> load() async {
    final raw = await _preferences.getString(key);
    if (raw == null) return const BacklightPolicy();
    final json = jsonDecode(raw);
    if (json is! Map<String, Object?>)
      throw const FormatException('invalid backlight settings');
    return BacklightPolicy.fromJson(json);
  }

  @override
  Future<void> save(BacklightPolicy policy) =>
      _preferences.setString(key, jsonEncode(policy.toJson()));
}
