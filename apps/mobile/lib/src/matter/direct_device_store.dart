import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/persian_digits.dart';
import 'electrical_measurement.dart';

final class DirectMatterDevice {
  const DirectMatterDevice({
    required this.nodeId,
    required this.name,
    required this.onOffEndpoints,
    this.channelNames = const <int, String>{},
    this.deviceTypes = const <int, List<int>>{},
    this.levelEndpoints = const <int>[],
    this.measurementCapabilities = const <int, Set<ElectricalMetric>>{},
  });

  final int nodeId;
  final String name;
  final List<int> onOffEndpoints;
  final Map<int, String> channelNames;
  final Map<int, List<int>> deviceTypes;
  final List<int> levelEndpoints;
  final Map<int, Set<ElectricalMetric>> measurementCapabilities;

  bool isSocket(int endpoint) =>
      (deviceTypes[endpoint] ?? const <int>[]).any((id) => id == 0x010a || id == 0x010b);

  String get productLabel {
    if (onOffEndpoints.isEmpty) return 'در انتظار شناسایی خروجی‌ها';
    if (onOffEndpoints.every(isSocket)) return 'پریز هوشمند';
    if (onOffEndpoints.any(isSocket)) return 'وسیلهٔ ترکیبی';
    // The number of OnOff endpoints does not prove physical switch gangs.
    return onOffEndpoints.length == 1
        ? 'کنترل تک‌خروجی'
        : 'کنترل ${toPersianDigits(onOffEndpoints.length)} خروجی مستقل';
  }

  String channelName(int endpoint, int index) =>
      channelNames[endpoint] ?? 'خروجی ${toPersianDigits(index + 1)}';

  DirectMatterDevice copyWith({
    String? name,
    List<int>? onOffEndpoints,
    Map<int, String>? channelNames,
    Map<int, List<int>>? deviceTypes,
    List<int>? levelEndpoints,
    Map<int, Set<ElectricalMetric>>? measurementCapabilities,
  }) => DirectMatterDevice(
    nodeId: nodeId,
    name: name ?? this.name,
    onOffEndpoints: onOffEndpoints ?? this.onOffEndpoints,
    channelNames: channelNames ?? this.channelNames,
    deviceTypes: deviceTypes ?? this.deviceTypes,
    levelEndpoints: levelEndpoints ?? this.levelEndpoints,
    measurementCapabilities:
        measurementCapabilities ?? this.measurementCapabilities,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeId': nodeId,
    'name': name,
    'onOffEndpoints': onOffEndpoints,
    'deviceTypes': deviceTypes.map((endpoint, types) => MapEntry(endpoint.toString(), types)),
    'levelEndpoints': levelEndpoints,
    'measurementCapabilities': measurementCapabilities.map(
      (endpoint, metrics) => MapEntry(
        endpoint.toString(),
        metrics.map((metric) => metric.name).toList(growable: false),
      ),
    ),
    'channelNames': channelNames.map(
      (endpoint, name) => MapEntry(endpoint.toString(), name),
    ),
  };

  factory DirectMatterDevice.fromJson(Map<String, Object?> json) {
    final nodeId = json['nodeId'];
    final name = json['name'];
    final endpoints = json['onOffEndpoints'];
    final rawNames = json['channelNames'];
    final rawTypes = json['deviceTypes'];
    final rawLevelEndpoints = json['levelEndpoints'];
    final rawMeasurementCapabilities = json['measurementCapabilities'];
    final types = <int, List<int>>{};
    if (rawTypes != null) {
      if (rawTypes is! Map<String, Object?>) throw const FormatException('invalid device types');
      for (final entry in rawTypes.entries) {
        final endpoint = int.tryParse(entry.key);
        final values = entry.value;
        if (endpoint == null || endpoint < 0 || values is! List ||
            values.any((value) => value is! int || value < 0)) {
          throw const FormatException('invalid device type entry');
        }
        types[endpoint] = List<int>.unmodifiable(values.cast<int>());
      }
    }
    if (nodeId is! int || name is! String || endpoints is! List<Object?> ||
        (rawLevelEndpoints != null && rawLevelEndpoints is! List<Object?>) ||
        (rawMeasurementCapabilities != null &&
            rawMeasurementCapabilities is! Map<String, Object?>)) {
      throw const FormatException('invalid direct Matter device');
    }
    final measurementCapabilities = <int, Set<ElectricalMetric>>{};
    if (rawMeasurementCapabilities is Map<String, Object?>) {
      for (final entry in rawMeasurementCapabilities.entries) {
        final endpoint = int.tryParse(entry.key);
        final rawMetrics = entry.value;
        if (endpoint == null || endpoint <= 0 || rawMetrics is! List<Object?>) {
          throw const FormatException('invalid measurement capabilities');
        }
        final metrics = <ElectricalMetric>{};
        for (final rawMetric in rawMetrics) {
          if (rawMetric is! String) {
            throw const FormatException('invalid measurement capability');
          }
          ElectricalMetric? metric;
          for (final candidate in ElectricalMetric.values) {
            if (candidate.name == rawMetric) {
              metric = candidate;
              break;
            }
          }
          if (metric != null) metrics.add(metric);
        }
        if (metrics.isNotEmpty) {
          measurementCapabilities[endpoint] =
              Set<ElectricalMetric>.unmodifiable(metrics);
        }
      }
    }
    final channelNames = <int, String>{};
    if (rawNames != null) {
      if (rawNames is! Map<String, Object?>) {
        throw const FormatException('invalid direct Matter channel names');
      }
      for (final entry in rawNames.entries) {
        final endpoint = int.tryParse(entry.key);
        final value = entry.value;
        if (endpoint == null || value is! String || value.trim().isEmpty) {
          throw const FormatException('invalid direct Matter channel name');
        }
        channelNames[endpoint] = value;
      }
    }
    return DirectMatterDevice(
      nodeId: nodeId,
      name: name,
      deviceTypes: Map<int, List<int>>.unmodifiable(types),
      levelEndpoints: (rawLevelEndpoints as List<Object?>? ?? const <Object?>[])
          .map((value) {
            if (value is! int || value <= 0) {
              throw const FormatException('invalid LevelControl endpoint');
            }
            return value;
          })
          .toList(growable: false),
      measurementCapabilities:
          Map<int, Set<ElectricalMetric>>.unmodifiable(
            measurementCapabilities,
          ),
      onOffEndpoints: endpoints
          .map((value) {
            if (value is! int) {
              throw const FormatException('invalid direct Matter endpoint');
            }
            return value;
          })
          .toList(growable: false),
      channelNames: Map<int, String>.unmodifiable(channelNames),
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
