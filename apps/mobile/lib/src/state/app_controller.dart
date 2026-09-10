import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/manisa_api.dart';
import '../data/models.dart';
import '../realtime/manisa_realtime.dart';

final class AppController extends ChangeNotifier {
  AppController({required ManisaApi api, required ManisaRealtime realtime})
      : _api = api,
        _realtime = realtime;

  final ManisaApi _api;
  final ManisaRealtime _realtime;

  List<Home> homes = const <Home>[];
  List<Room> rooms = const <Room>[];
  List<Device> devices = const <Device>[];
  String? selectedHomeId;
  bool loading = false;
  String? errorMessage;

  final Map<String, DeviceDescriptor> _descriptors = <String, DeviceDescriptor>{};
  final Map<String, Map<String, DeviceState>> _states = <String, Map<String, DeviceState>>{};
  StreamSubscription<ManisaEvent>? _events;

  DeviceDescriptor? descriptorFor(String deviceId) => _descriptors[deviceId];

  DeviceState? stateFor(String deviceId, int endpoint, String capability) =>
      _states[deviceId]?['$endpoint:$capability'];

  Future<void> initialize() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      homes = await _api.listHomes();
      if (homes.isNotEmpty) {
        await selectHome(homes.first.id, notifyLoading: false);
      }
      _listenRealtime();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectHome(String homeId, {bool notifyLoading = true}) async {
    selectedHomeId = homeId;
    if (notifyLoading) {
      loading = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        _api.listRooms(homeId),
        _api.listDevices(homeId),
      ]);
      rooms = results[0] as List<Room>;
      devices = results[1] as List<Device>;
      await Future.wait<void>(devices.map(_loadDevice));
      errorMessage = null;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      if (notifyLoading) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadDevice(Device device) async {
    final results = await Future.wait<Object>(<Future<Object>>[
      _api.deviceDescriptor(device.id),
      _api.deviceStates(device.id),
    ]);
    _descriptors[device.id] = results[0] as DeviceDescriptor;
    final states = results[1] as List<DeviceState>;
    _states[device.id] = <String, DeviceState>{
      for (final state in states) state.key: state,
    };
  }

  Future<void> sendCommand({
    required String deviceId,
    required int endpoint,
    required String capability,
    required String action,
    JsonMap params = const <String, Object?>{},
  }) async {
    await _api.executeCommand(
      deviceId: deviceId,
      endpoint: endpoint,
      capability: capability,
      action: action,
      params: params,
    );
  }

  void _listenRealtime() {
    if (_events != null) {
      return;
    }
    _events = _realtime.connect().listen(
      (event) {
        if (event.type != 'device.state_changed') {
          return;
        }
        final state = DeviceState(
          deviceId: event.deviceId,
          endpoint: event.endpoint,
          capability: event.capability,
          value: event.value,
        );
        (_states[event.deviceId] ??= <String, DeviceState>{})[state.key] = state;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        errorMessage = 'Realtime disconnected: $error';
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }
}
