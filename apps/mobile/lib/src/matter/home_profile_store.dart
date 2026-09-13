import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class ManisaHomeProfile {
  const ManisaHomeProfile({this.name = defaultName});

  static const String defaultName = 'خانهٔ من';

  final String name;

  ManisaHomeProfile rename(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'home name cannot be empty');
    }
    return ManisaHomeProfile(name: normalized);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'name': name,
      };

  factory ManisaHomeProfile.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('invalid home profile');
    }
    return ManisaHomeProfile(name: name.trim());
  }
}

abstract interface class HomeProfileStore {
  Future<ManisaHomeProfile> load();
  Future<void> save(ManisaHomeProfile profile);
}

final class EmptyHomeProfileStore implements HomeProfileStore {
  const EmptyHomeProfileStore();

  @override
  Future<ManisaHomeProfile> load() async => const ManisaHomeProfile();

  @override
  Future<void> save(ManisaHomeProfile profile) async {}
}

final class PreferencesHomeProfileStore implements HomeProfileStore {
  PreferencesHomeProfileStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _key = 'manisa_home_profile_v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<ManisaHomeProfile> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const ManisaHomeProfile();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const ManisaHomeProfile();
      return ManisaHomeProfile.fromJson(decoded);
    } on FormatException {
      return const ManisaHomeProfile();
    }
  }

  @override
  Future<void> save(ManisaHomeProfile profile) =>
      _preferences.setString(_key, jsonEncode(profile.toJson()));
}
