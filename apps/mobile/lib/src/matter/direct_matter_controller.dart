import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'color_control.dart';
import 'electrical_measurement.dart';
import 'power_source.dart';
import 'sensor_measurement.dart';

abstract interface class LocalDeviceForgetter {
  Future<void> forgetDeviceLocally(int nodeId);
}

abstract interface class PowerSourceController {
  Future<Map<int, PowerSource>> readPowerSources(int nodeId);
}

abstract interface class SensorMeasurementController {
  Future<Map<int, DirectSensorMeasurement>> readSensorMeasurements(int nodeId);
  Stream<DirectSensorEvent> watchSensorMeasurements();
}

abstract interface class ColorControlController {
  Future<Map<int, DirectColorState>> readColors(int nodeId);
  Future<void> setColor({required int nodeId, required int endpoint,
    required String mode, required int first, required int second});
  Stream<DirectColorEvent> watchColors();
}

final class DirectMatterCommissionResult {
  const DirectMatterCommissionResult({
    required this.nodeId,
    required this.onOffEndpoints,
  });

  final int nodeId;
  final List<int> onOffEndpoints;

  factory DirectMatterCommissionResult.fromMap(Map<Object?, Object?> value) {
    final nodeId = value['nodeId'];
    final endpoints = value['onOffEndpoints'];
    if (nodeId is! int || endpoints is! List<Object?>) {
      throw const FormatException('invalid Matter commissioning result');
    }
    return DirectMatterCommissionResult(
      nodeId: nodeId,
      onOffEndpoints: endpoints.map((item) {
        if (item is! int) {
          throw const FormatException('invalid Matter endpoint');
        }
        return item;
      }).toList(growable: false),
    );
  }
}

final class DirectMatterOnOffEvent {
  const DirectMatterOnOffEvent({
    required this.nodeId,
    required this.endpoint,
    required this.value,
  });

  final int nodeId;
  final int endpoint;
  final bool value;

  factory DirectMatterOnOffEvent.fromMap(Map<Object?, Object?> value) {
    final nodeId = value['nodeId'];
    final endpoint = value['endpoint'];
    final state = value['value'];
    if (nodeId is! int || endpoint is! int || state is! bool) {
      throw const FormatException('invalid Matter OnOff event');
    }
    return DirectMatterOnOffEvent(
      nodeId: nodeId,
      endpoint: endpoint,
      value: state,
    );
  }
}

final class DirectMatterLevelEvent {
  const DirectMatterLevelEvent({
    required this.nodeId,
    required this.endpoint,
    required this.level,
  });

  final int nodeId;
  final int endpoint;
  final int? level;

  factory DirectMatterLevelEvent.fromMap(Map<Object?, Object?> value) {
    final nodeId = value['nodeId'];
    final endpoint = value['endpoint'];
    final level = value['level'];
    if (nodeId is! int ||
        endpoint is! int ||
        (level != null && (level is! int || level < 1 || level > 254))) {
      throw const FormatException('invalid Matter LevelControl event');
    }
    return DirectMatterLevelEvent(
      nodeId: nodeId,
      endpoint: endpoint,
      level: level as int?,
    );
  }
}

abstract interface class DirectMatterController {
  Future<bool> isSupported();

  Future<DirectMatterCommissionResult> commissionWifi({
    required String setupPayload,
    required String ssid,
    required String password,
  });

  Future<List<int>> discoverOnOffEndpoints(int nodeId);

  Future<bool> readOnOff({required int nodeId, required int endpoint});

  Future<void> setOnOff({
    required int nodeId,
    required int endpoint,
    required bool value,
  });

  Future<void> toggleOnOff({required int nodeId, required int endpoint});

  Stream<DirectMatterOnOffEvent> watchOnOff();

  Future<void> removeDevice(int nodeId);
}

abstract interface class DeviceTypeReader {
  Future<Map<int, List<int>>> readDeviceTypes(int nodeId);
}

abstract interface class LevelControlController {
  Future<Map<int, int?>> readLevels(int nodeId);

  Future<void> setLevel({
    required int nodeId,
    required int endpoint,
    required int level,
  });
}

abstract interface class LevelEventController {
  Stream<DirectMatterLevelEvent> watchLevels();
}

abstract interface class ElectricalMeasurementController {
  Future<Map<int, DirectElectricalMeasurement>> readElectricalMeasurements(
    int nodeId,
  );
}

abstract interface class ElectricalMeasurementEventController {
  Stream<DirectElectricalEvent> watchElectricalMeasurements();
}

final class PlatformDirectMatterController
    implements
        DirectMatterController,
        DeviceTypeReader,
        LevelControlController,
        LevelEventController,
        ColorControlController,
        SensorMeasurementController,
        PowerSourceController,
        LocalDeviceForgetter,
        ElectricalMeasurementController,
        ElectricalMeasurementEventController {
  const PlatformDirectMatterController({
    MethodChannel methods = const MethodChannel(_methodChannelName),
    EventChannel events = const EventChannel(_eventChannelName),
    EventChannel levelEvents = const EventChannel(_levelEventChannelName),
    EventChannel colorEvents = const EventChannel('com.manisa/matter/color_events'),
    EventChannel electricalEvents = const EventChannel('com.manisa/matter/electrical_events'),
    EventChannel sensorEvents = const EventChannel('com.manisa/matter/sensor_events'),
  })  : _methods = methods,
        _events = events,
        _levelEvents = levelEvents,
        _colorEvents = colorEvents,
        _electricalEvents = electricalEvents,
        _sensorEvents = sensorEvents;

  static const String _methodChannelName = 'com.manisa/matter/methods';
  static const String _eventChannelName = 'com.manisa/matter/events';
  static const String _levelEventChannelName = 'com.manisa/matter/level_events';

  final MethodChannel _methods;
  final EventChannel _events;
  final EventChannel _levelEvents;
  final EventChannel _colorEvents;
  final EventChannel _electricalEvents;
  final EventChannel _sensorEvents;

  @override
  Future<Map<int, PowerSource>> readPowerSources(int nodeId) async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>(
      'readPowerSources', <String, Object?>{'nodeId': nodeId});
    if (raw == null) throw const FormatException('missing power source response');
    final result = <int, PowerSource>{};
    for (final entry in raw.entries) {
      final endpoint = int.tryParse(entry.key.toString());
      if (endpoint == null || endpoint < 0 || endpoint > 65534 ||
          entry.value is! Map<Object?, Object?>) {
        throw const FormatException('invalid power source endpoint');
      }
      result[endpoint] = PowerSource.fromMap(entry.value! as Map<Object?, Object?>);
    }
    return result;
  }

  @override
  Future<Map<int, DirectSensorMeasurement>> readSensorMeasurements(int nodeId) async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>(
      'readSensorMeasurements', <String, Object?>{'nodeId': nodeId});
    if (raw == null) throw const FormatException('missing sensor response');
    final result = <int, DirectSensorMeasurement>{};
    for (final entry in raw.entries) {
      final endpoint = int.tryParse(entry.key.toString());
      if (endpoint == null || endpoint <= 0 || endpoint > 65534 ||
          entry.value is! Map<Object?, Object?>) {
        throw const FormatException('invalid sensor response');
      }
      result[endpoint] = DirectSensorMeasurement.fromMap(entry.value! as Map<Object?, Object?>);
    }
    return result;
  }

  @override
  Stream<DirectSensorEvent> watchSensorMeasurements() =>
      _sensorEvents.receiveBroadcastStream().map((event) {
        if (event is! Map<Object?, Object?>) throw const FormatException('invalid sensor event');
        return DirectSensorEvent.fromMap(event);
      });

  @override
  Stream<DirectElectricalEvent> watchElectricalMeasurements() =>
      _electricalEvents.receiveBroadcastStream().map((event) {
        if (event is! Map<Object?, Object?>) {
          throw const FormatException('invalid electrical event');
        }
        return DirectElectricalEvent.fromMap(event);
      });

  @override
  Future<Map<int, DirectColorState>> readColors(int nodeId) async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>(
        'readColors', <String, Object?>{'nodeId': nodeId});
    if (raw == null) throw const FormatException('missing color response');
    final result = <int, DirectColorState>{};
    for (final entry in raw.entries) {
      final endpoint = int.tryParse(entry.key.toString());
      if (endpoint == null || endpoint <= 0 || entry.value is! Map<Object?, Object?>) {
        throw const FormatException('invalid color response');
      }
      final color = DirectColorState.fromMap(entry.value! as Map<Object?, Object?>);
      if (color.supportsColor) result[endpoint] = color;
    }
    return result;
  }

  @override
  Future<void> setColor({required int nodeId, required int endpoint,
    required String mode, required int first, required int second}) {
    final maximum = mode == 'hs' ? 254 : 65279;
    if ((mode != 'hs' && mode != 'xy') || endpoint <= 0 ||
        first < 0 || first > maximum || second < 0 || second > maximum ||
        (mode == 'xy' && (second == 0 || first + second > 65536))) {
      throw ArgumentError('invalid color command');
    }
    return _methods.invokeMethod<void>('setColor', <String, Object?>{
      'nodeId': nodeId, 'endpoint': endpoint, 'mode': mode,
      'first': first, 'second': second,
    });
  }

  @override
  Stream<DirectColorEvent> watchColors() => _colorEvents.receiveBroadcastStream()
      .map((event) {
        if (event is! Map<Object?, Object?>) {
          throw const FormatException('invalid color event');
        }
        return DirectColorEvent.fromMap(event);
      });

  @override
  Future<Map<int, DirectElectricalMeasurement>> readElectricalMeasurements(
    int nodeId,
  ) async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>(
      'readElectricalMeasurements',
      <String, Object?>{'nodeId': nodeId},
    );
    if (raw == null) {
      throw const FormatException('missing electrical measurement response');
    }
    final result = <int, DirectElectricalMeasurement>{};
    for (final entry in raw.entries) {
      final endpoint = int.tryParse(entry.key.toString());
      final measurement = entry.value;
      if (endpoint == null ||
          endpoint <= 0 ||
          measurement is! Map<Object?, Object?>) {
        throw const FormatException('invalid electrical measurement response');
      }
      result[endpoint] = DirectElectricalMeasurement.fromMap(measurement);
    }
    return result;
  }

  @override
  Future<Map<int, List<int>>> readDeviceTypes(int nodeId) async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>(
      'readDeviceTypes', <String, Object?>{'nodeId': nodeId},
    );
    if (raw == null) throw const FormatException('missing device types');
    final result = <int, List<int>>{};
    for (final entry in raw.entries) {
      final endpoint = int.tryParse(entry.key.toString());
      final values = entry.value;
      if (endpoint == null || endpoint < 0 || values is! List ||
          values.any((value) => value is! int || value < 0)) {
        throw const FormatException('invalid device types');
      }
      result[endpoint] = List<int>.unmodifiable(values.cast<int>());
    }
    return result;
  }

  @override
  Future<Map<int, int?>> readLevels(int nodeId) async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>(
      'readLevels', <String, Object?>{'nodeId': nodeId},
    );
    if (raw == null) throw const FormatException('missing LevelControl response');
    final result = <int, int?>{};
    for (final entry in raw.entries) {
      final endpoint = int.tryParse(entry.key.toString());
      final level = entry.value;
      if (endpoint == null || endpoint <= 0 ||
          (level != null && (level is! int || level < 1 || level > 254))) {
        throw const FormatException('invalid LevelControl response');
      }
      result[endpoint] = level as int?;
    }
    return result;
  }

  @override
  Future<void> setLevel({required int nodeId, required int endpoint, required int level}) {
    if (level < 1 || level > 254) {
      throw RangeError.range(level, 1, 254, 'level');
    }
    return _methods.invokeMethod<void>('setLevel', <String, Object?>{
      'nodeId': nodeId, 'endpoint': endpoint, 'level': level,
    });
  }

  @override
  Future<bool> isSupported() async =>
      await _methods.invokeMethod<bool>('isSupported') ?? false;

  @override
  Future<DirectMatterCommissionResult> commissionWifi({
    required String setupPayload,
    required String ssid,
    required String password,
  }) async {
    if (!setupPayload.startsWith('MT:')) {
      throw ArgumentError.value(
        setupPayload,
        'setupPayload',
        'Matter QR payload must start with MT:',
      );
    }
    if (ssid.trim().isEmpty) {
      throw ArgumentError.value(ssid, 'ssid', 'Wi-Fi SSID is required');
    }

    debugPrint('ManisaMatter: commissionWifi invoked');
    final result = await _methods.invokeMethod<Object?>(
      'commissionWifi',
      <String, Object?>{
        'setupPayload': setupPayload,
        'ssid': ssid,
        'password': password,
      },
    );
    if (result is! Map<Object?, Object?>) {
      throw const FormatException('invalid Matter commissioning response');
    }
    return DirectMatterCommissionResult.fromMap(result);
  }

  @override
  Future<List<int>> discoverOnOffEndpoints(int nodeId) async {
    final result = await _methods.invokeListMethod<Object?>(
      'discoverOnOffEndpoints',
      <String, Object?>{'nodeId': nodeId},
    );
    if (result == null) {
      return const <int>[];
    }
    return result.map((item) {
      if (item is! int) {
        throw const FormatException('invalid Matter endpoint');
      }
      return item;
    }).toList(growable: false);
  }

  @override
  Future<bool> readOnOff({required int nodeId, required int endpoint}) async {
    final result = await _methods.invokeMethod<bool>(
      'readOnOff',
      <String, Object?>{'nodeId': nodeId, 'endpoint': endpoint},
    );
    if (result == null) {
      throw PlatformException(
        code: 'matter_invalid_response',
        message: 'Matter bridge returned no OnOff state',
      );
    }
    return result;
  }

  @override
  Future<void> setOnOff({
    required int nodeId,
    required int endpoint,
    required bool value,
  }) =>
      _methods.invokeMethod<void>(
        'setOnOff',
        <String, Object?>{
          'nodeId': nodeId,
          'endpoint': endpoint,
          'value': value,
        },
      );

  @override
  Future<void> toggleOnOff({required int nodeId, required int endpoint}) =>
      _methods.invokeMethod<void>(
        'toggleOnOff',
        <String, Object?>{'nodeId': nodeId, 'endpoint': endpoint},
      );

  @override
  Stream<DirectMatterOnOffEvent> watchOnOff() => _events
      .receiveBroadcastStream()
      .where((event) => event is Map<Object?, Object?>)
      .cast<Map<Object?, Object?>>()
      .map(DirectMatterOnOffEvent.fromMap);

  @override
  Stream<DirectMatterLevelEvent> watchLevels() => _levelEvents
      .receiveBroadcastStream()
      .where((event) => event is Map<Object?, Object?>)
      .cast<Map<Object?, Object?>>()
      .map(DirectMatterLevelEvent.fromMap);

  @override
  Future<void> forgetDeviceLocally(int nodeId) => _methods.invokeMethod<void>(
    'forgetDeviceLocally', <String, Object?>{'nodeId': nodeId});

  @override
  Future<void> removeDevice(int nodeId) => _methods.invokeMethod<void>(
        'removeDevice',
        <String, Object?>{'nodeId': nodeId},
      );
}
