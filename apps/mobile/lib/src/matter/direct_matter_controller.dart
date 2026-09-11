import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

final class PlatformDirectMatterController implements DirectMatterController {
  const PlatformDirectMatterController({
    MethodChannel methods = const MethodChannel(_methodChannelName),
    EventChannel events = const EventChannel(_eventChannelName),
  })  : _methods = methods,
        _events = events;

  static const String _methodChannelName = 'com.manisa/matter/methods';
  static const String _eventChannelName = 'com.manisa/matter/events';

  final MethodChannel _methods;
  final EventChannel _events;

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
  Future<void> removeDevice(int nodeId) => _methods.invokeMethod<void>(
        'removeDevice',
        <String, Object?>{'nodeId': nodeId},
      );
}
