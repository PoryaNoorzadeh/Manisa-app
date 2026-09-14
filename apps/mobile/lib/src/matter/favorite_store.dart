import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class FavoriteOutput {
  const FavoriteOutput({required this.nodeId, required this.endpoint});

  final int nodeId;
  final int endpoint;

  Map<String, Object?> toJson() => <String, Object?>{
        'nodeId': nodeId,
        'endpoint': endpoint,
      };

  factory FavoriteOutput.fromJson(Map<String, Object?> json) {
    final nodeId = json['nodeId'];
    final endpoint = json['endpoint'];
    if (nodeId is! int || endpoint is! int || nodeId < 0 || endpoint < 0) {
      throw const FormatException('invalid favorite output');
    }
    return FavoriteOutput(nodeId: nodeId, endpoint: endpoint);
  }

  @override
  bool operator ==(Object other) =>
      other is FavoriteOutput &&
      other.nodeId == nodeId &&
      other.endpoint == endpoint;

  @override
  int get hashCode => Object.hash(nodeId, endpoint);
}

final class FavoriteCatalog {
  const FavoriteCatalog({this.outputs = const <FavoriteOutput>[]});

  final List<FavoriteOutput> outputs;

  bool contains(int nodeId, int endpoint) => outputs.contains(
        FavoriteOutput(nodeId: nodeId, endpoint: endpoint),
      );

  FavoriteCatalog toggle(int nodeId, int endpoint) {
    final output = FavoriteOutput(nodeId: nodeId, endpoint: endpoint);
    if (outputs.contains(output)) {
      return FavoriteCatalog(
        outputs: List<FavoriteOutput>.unmodifiable(
          outputs.where((item) => item != output),
        ),
      );
    }
    return FavoriteCatalog(
      outputs: List<FavoriteOutput>.unmodifiable(<FavoriteOutput>[
        ...outputs,
        output,
      ]),
    );
  }

  FavoriteCatalog removeDevice(int nodeId) => FavoriteCatalog(
        outputs: List<FavoriteOutput>.unmodifiable(
          outputs.where((output) => output.nodeId != nodeId),
        ),
      );

  FavoriteCatalog retain(bool Function(FavoriteOutput output) predicate) =>
      FavoriteCatalog(
        outputs: List<FavoriteOutput>.unmodifiable(outputs.where(predicate)),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'outputs': outputs.map((output) => output.toJson()).toList(),
      };

  factory FavoriteCatalog.fromJson(Map<String, Object?> json) {
    final rawOutputs = json['outputs'];
    if (rawOutputs is! List<Object?>) {
      throw const FormatException('invalid favorite catalog');
    }
    final outputs = rawOutputs.map((value) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('invalid favorite entry');
      }
      return FavoriteOutput.fromJson(value);
    }).toList(growable: false);
    if (outputs.toSet().length != outputs.length) {
      throw const FormatException('duplicate favorite output');
    }
    return FavoriteCatalog(
      outputs: List<FavoriteOutput>.unmodifiable(outputs),
    );
  }
}

abstract interface class FavoriteStore {
  Future<FavoriteCatalog> load();
  Future<void> save(FavoriteCatalog catalog);
}

final class EmptyFavoriteStore implements FavoriteStore {
  const EmptyFavoriteStore();

  @override
  Future<FavoriteCatalog> load() async => const FavoriteCatalog();

  @override
  Future<void> save(FavoriteCatalog catalog) async {}
}

final class PreferencesFavoriteStore implements FavoriteStore {
  PreferencesFavoriteStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _key = 'manisa_favorite_catalog_v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<FavoriteCatalog> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const FavoriteCatalog();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const FavoriteCatalog();
      return FavoriteCatalog.fromJson(decoded);
    } on FormatException {
      return const FavoriteCatalog();
    }
  }

  @override
  Future<void> save(FavoriteCatalog catalog) =>
      _preferences.setString(_key, jsonEncode(catalog.toJson()));
}
