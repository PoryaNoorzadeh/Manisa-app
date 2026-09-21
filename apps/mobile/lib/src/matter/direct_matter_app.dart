import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/persian_digits.dart';
import 'color_control.dart';
import 'color_control_widget.dart';
import 'direct_device_store.dart';
import 'direct_matter_controller.dart';
import 'electrical_measurement.dart';
import 'favorite_store.dart';
import 'home_profile_store.dart';
import 'level_control.dart';
import 'power_source_widget.dart';
import 'room_store.dart';
import 'sensor_measurement.dart';
import 'sensor_measurement_widget.dart';

final class ManisaDirectApp extends StatelessWidget {
  const ManisaDirectApp({
    required this.controller,
    required this.deviceStore,
    this.favoriteStore = const EmptyFavoriteStore(),
    this.homeStore = const EmptyHomeProfileStore(),
    this.roomStore = const EmptyRoomStore(),
    super.key,
  });

  final DirectMatterController controller;
  final DirectDeviceStore deviceStore;
  final FavoriteStore favoriteStore;
  final HomeProfileStore homeStore;
  final RoomStore roomStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مانیسا',
      locale: const Locale('fa'),
      supportedLocales: const <Locale>[Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF006C70),
        scaffoldBackgroundColor: const Color(0xFFF3F7F6),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 56)),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: DirectMatterHomeScreen(
        controller: controller,
        deviceStore: deviceStore,
        favoriteStore: favoriteStore,
        homeStore: homeStore,
        roomStore: roomStore,
      ),
    );
  }
}

final class DirectMatterHomeScreen extends StatefulWidget {
  const DirectMatterHomeScreen({
    required this.controller,
    required this.deviceStore,
    required this.favoriteStore,
    required this.homeStore,
    required this.roomStore,
    super.key,
  });

  final DirectMatterController controller;
  final DirectDeviceStore deviceStore;
  final FavoriteStore favoriteStore;
  final HomeProfileStore homeStore;
  final RoomStore roomStore;

  @override
  State<DirectMatterHomeScreen> createState() => _DirectMatterHomeScreenState();
}

final class _DirectMatterHomeScreenState extends State<DirectMatterHomeScreen>
    with WidgetsBindingObserver {
  List<DirectMatterDevice> _devices = const <DirectMatterDevice>[];
  RoomCatalog _roomCatalog = const RoomCatalog();
  ManisaHomeProfile _homeProfile = const ManisaHomeProfile();
  FavoriteCatalog _favorites = const FavoriteCatalog();
  final Map<String, SensorObservation> _sensorObservations = <String, SensorObservation>{};
  final Map<int, Object> _sensorLifetimes = <int, Object>{};
  final Set<int> _readingSensors = <int>{};
  StreamSubscription<DirectSensorEvent>? _sensorEvents;
  Timer? _sensorFreshnessTimer;
  final Map<String, bool> _states = <String, bool>{};
  final Map<String, int> _levels = <String, int>{};
  final Map<String, DirectColorState> _colors = <String, DirectColorState>{};
  final Set<String> _staleColors = <String>{};
  final Set<int> _readingColors = <int>{};
  final Map<int, Object> _colorLifetimes = <int, Object>{};
  final Map<String, int> _colorRevisions = <String, int>{};
  StreamSubscription<DirectColorEvent>? _colorEvents;
  final Map<String, DirectElectricalMeasurement> _electricalMeasurements =
      <String, DirectElectricalMeasurement>{};
  final Map<String, Set<ElectricalMetric>> _staleElectricalMetrics =
      <String, Set<ElectricalMetric>>{};
  final Set<String> _busy = <String>{};
  StreamSubscription<DirectMatterOnOffEvent>? _events;
  StreamSubscription<DirectMatterLevelEvent>? _levelEvents;
  StreamSubscription<DirectElectricalEvent>? _electricalEvents;
  final Set<int> _refreshingNodes = <int>{};
  final Set<int> _readingCapabilities = <int>{};
  final Set<int> _removingNodes = <int>{};
  final Set<int> _unavailableNodes = <int>{};
  final Map<int, String> _deviceErrors = <int, String>{};
  static const _readTimeout = Duration(seconds: 15);
  bool _loading = true;
  bool _editingMetadata = false;
  bool _retrying = false;
  DateTime? _lastResumeRefresh;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel());
    unawaited(_levelEvents?.cancel());
    unawaited(_colorEvents?.cancel());
    unawaited(_electricalEvents?.cancel());
    unawaited(_sensorEvents?.cancel());
    _sensorFreshnessTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _loading || _devices.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final previous = _lastResumeRefresh;
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 2)) {
      return;
    }
    _lastResumeRefresh = now;
    unawaited(_refreshAllStates());
  }

  String _stateKey(int nodeId, int endpoint) => '$nodeId:$endpoint';

  Future<void> _initialize() async {
    try {
      final supported = await widget.controller.isSupported();
      if (!supported) {
        throw StateError('Direct Matter is not available on this device.');
      }
      final loaded = await Future.wait<Object>(<Future<Object>>[
        widget.deviceStore.load(),
        widget.roomStore.load(),
        widget.homeStore.load(),
        widget.favoriteStore.load(),
      ]);
      final devices = loaded[0] as List<DirectMatterDevice>;
      final roomCatalog = loaded[1] as RoomCatalog;
      final homeProfile = loaded[2] as ManisaHomeProfile;
      final favorites = loaded[3] as FavoriteCatalog;
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _roomCatalog = roomCatalog;
        _homeProfile = homeProfile;
        _favorites = favorites.retain(
          (favorite) => devices.any(
            (device) =>
                device.nodeId == favorite.nodeId &&
                device.onOffEndpoints.contains(favorite.endpoint),
          ),
        );
      });
      _events = widget.controller.watchOnOff().listen(
        (event) {
          if (!_canUpdate(event.nodeId)) return;
          setState(() {
            _states[_stateKey(event.nodeId, event.endpoint)] = event.value;
            _unavailableNodes.remove(event.nodeId);
            _deviceErrors.remove(event.nodeId);
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!mounted) return;
          setState(() => _error = 'Realtime Matter update failed: $error');
        },
      );
      final controller = widget.controller;
      if (controller is LevelEventController) {
        _levelEvents = (controller as LevelEventController).watchLevels().listen(
          (event) {
            if (!_canUpdate(event.nodeId)) return;
            final device = _devices.firstWhere(
              (item) => item.nodeId == event.nodeId,
            );
            if (!device.levelEndpoints.contains(event.endpoint)) return;
            setState(() {
              final key = _stateKey(event.nodeId, event.endpoint);
              if (event.level == null) {
                _levels.remove(key);
              } else {
                _levels[key] = event.level!;
              }
              _unavailableNodes.remove(event.nodeId);
              _deviceErrors.remove(event.nodeId);
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!mounted) return;
            setState(() => _error = 'Realtime dimmer update failed: $error');
          },
        );
      }
      if (controller is ColorControlController) {
        _colorEvents = (controller as ColorControlController).watchColors().listen((event) {
          if (!_canUpdate(event.nodeId)) return;
          final device = _devices.firstWhere((item) => item.nodeId == event.nodeId);
          if (!device.colorCapabilities.containsKey(event.endpoint)) return;
          final key = _stateKey(event.nodeId, event.endpoint);
          setState(() {
            if (event.stale) {
              _staleColors.add(key);
            } else {
              final previous = _colors[key] ?? DirectColorState.fromMap(
                  <String, int>{'capabilities': device.colorCapabilities[event.endpoint]!});
              _colors[key] = previous.merge(event.report);
              _colorRevisions[key] = (_colorRevisions[key] ?? 0) + 1;
              // A partial report cannot make a failed full read fresh.
              if (DirectColorState.fromMap(<String, int?>{
                  'capabilities': device.colorCapabilities[event.endpoint],
                  ...event.report.values,
                }).hsv != null && !_unavailableNodes.contains(event.nodeId)) {
                _staleColors.remove(key);
              }
            }
          });
        }, onError: (Object error, StackTrace stack) {
          if (!mounted) return;
          setState(() => _staleColors.addAll(_colors.keys));
        });
      }
      if (controller is ElectricalMeasurementEventController) {
        _electricalEvents = (controller as ElectricalMeasurementEventController)
            .watchElectricalMeasurements().listen((event) {
          if (!_canUpdate(event.nodeId)) return;
          final device = _devices.firstWhere((item) => item.nodeId == event.nodeId);
          final supported = device.measurementCapabilities[event.endpoint];
          if (supported == null) return;
          final key = _stateKey(event.nodeId, event.endpoint);
          setState(() {
            final stale = <ElectricalMetric>{
              ...?_staleElectricalMetrics[key],
              ...event.staleMetrics.where(supported.contains),
            };
            final report = event.report;
            if (report != null) {
              final accepted = report.supported.intersection(supported);
              if (accepted.isNotEmpty) {
                final filtered = DirectElectricalMeasurement(
                  supported: accepted,
                  activePowerMilliwatts: report.activePowerMilliwatts,
                  voltageMillivolts: report.voltageMillivolts,
                  activeCurrentMilliamps: report.activeCurrentMilliamps,
                  cumulativeEnergyImportedMilliwattHours:
                      report.cumulativeEnergyImportedMilliwattHours,
                );
                _electricalMeasurements[key] =
                    _electricalMeasurements[key]?.merge(filtered) ?? filtered;
                stale.removeAll(accepted);
              }
            }
            if (stale.isEmpty) _staleElectricalMetrics.remove(key);
            else _staleElectricalMetrics[key] = stale;
          });
        }, onError: (Object error, StackTrace stack) {
          if (!mounted) return;
          setState(() {
            for (final device in _devices) {
              for (final entry in device.measurementCapabilities.entries) {
                _staleElectricalMetrics[_stateKey(device.nodeId, entry.key)] =
                    Set<ElectricalMetric>.of(entry.value);
              }
            }
          });
        });
      }
      if (controller is SensorMeasurementController) {
        _sensorEvents = (controller as SensorMeasurementController).watchSensorMeasurements().listen((event) {
          if (!_canUpdate(event.nodeId)) return;
          final device = _devices.firstWhere((item) => item.nodeId == event.nodeId);
          final supported = device.sensorCapabilities[event.endpoint];
          if (supported == null) return;
          final key = _stateKey(event.nodeId, event.endpoint);
          setState(() {
            final observation = _sensorObservations.putIfAbsent(key, SensorObservation.new);
            observation.markStale(event.staleMetrics.intersection(supported));
            final report = event.report;
            if (report != null) {
              final filtered = <SensorMetric, int?>{
                for (final entry in report.values.entries)
                  if (supported.contains(entry.key)) entry.key: entry.value,
              };
              observation.report(DirectSensorMeasurement(filtered), DateTime.now());
              if (filtered.isNotEmpty && device.onOffEndpoints.isEmpty) {
                _unavailableNodes.remove(event.nodeId);
                if (_deviceErrors[event.nodeId]?.startsWith('Sensor read failed') == true) {
                  _deviceErrors.remove(event.nodeId);
                }
              }
            }
          });
        }, onError: (Object error, StackTrace stack) {
          if (!mounted) return;
          setState(() {
            for (final device in _devices) { _markSensorsStale(device); }
          });
        });
      }
      // Restore live state without blocking the home screen or onboarding.
      unawaited(_refreshAllStates());
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool _canUpdate(int nodeId) =>
      mounted &&
      !_removingNodes.contains(nodeId) &&
      _devices.any((device) => device.nodeId == nodeId);

  Future<void> _refreshAllStates() async {
    await Future.wait(
      List<DirectMatterDevice>.of(_devices).map(_refreshDevice),
    );
  }

  Future<void> _refreshDevice(DirectMatterDevice device) async {
    if (!_canUpdate(device.nodeId) || !_refreshingNodes.add(device.nodeId)) {
      return;
    }
    try {
      // Known endpoints are read before discovery so a discovery failure never
      // hides values that were already confirmed.
      for (final endpoint in device.onOffEndpoints) {
        final value = await widget.controller
            .readOnOff(nodeId: device.nodeId, endpoint: endpoint)
            .timeout(_readTimeout);
        if (!_canUpdate(device.nodeId)) return;
        setState(() {
          _states[_stateKey(device.nodeId, endpoint)] = value;
        });
      }
      if (!_canUpdate(device.nodeId)) return;
      final discovered = await widget.controller
          .discoverOnOffEndpoints(device.nodeId)
          .timeout(_readTimeout);
      if (!_canUpdate(device.nodeId)) return;
      if (discovered.isNotEmpty &&
          !_sameEndpoints(discovered, device.onOffEndpoints)) {
        final index = _devices.indexWhere(
          (item) => item.nodeId == device.nodeId,
        );
        if (index < 0) return;
        setState(() {
          final updated = List<DirectMatterDevice>.of(_devices);
          updated[index] = updated[index].copyWith(onOffEndpoints: discovered);
          _devices = updated;
        });
        try {
          await widget.deviceStore.save(_devices[index]);
        } catch (error) {
          if (_canUpdate(device.nodeId)) {
            setState(() {
              _deviceErrors[device.nodeId] =
                  'Could not save discovered channels: $error';
            });
          }
        }
        for (final endpoint in discovered.where(
          (e) => !device.onOffEndpoints.contains(e),
        )) {
          final value = await widget.controller
              .readOnOff(nodeId: device.nodeId, endpoint: endpoint)
              .timeout(_readTimeout);
          if (!_canUpdate(device.nodeId)) return;
          setState(() {
            _states[_stateKey(device.nodeId, endpoint)] = value;
          });
        }
      }
      if (_canUpdate(device.nodeId)) {
        setState(() {
          _unavailableNodes.remove(device.nodeId);
          if (!(_deviceErrors[device.nodeId]?.startsWith(
                'Could not save discovered channels',
              ) ??
              false)) {
            _deviceErrors.remove(device.nodeId);
          }
        });
        unawaited(_refreshOptionalControls(device.nodeId));
      }
    } catch (error) {
      if (_canUpdate(device.nodeId)) {
        setState(() {
          _unavailableNodes.add(device.nodeId);
          _deviceErrors[device.nodeId] =
              'Could not refresh ${device.name}: $error';
        });
        if (device.onOffEndpoints.isEmpty) await _refreshSensors(device.nodeId);
      }
    } finally {
      _refreshingNodes.remove(device.nodeId);
    }
  }

  void _markSensorsStale(DirectMatterDevice device) {
    for (final entry in device.sensorCapabilities.entries) {
      _sensorObservations.putIfAbsent(_stateKey(device.nodeId, entry.key), SensorObservation.new)
          .markStale(entry.value);
    }
  }

  Future<void> _refreshSensors(int nodeId) async {
    final controller = widget.controller;
    if (controller is! SensorMeasurementController || !_canUpdate(nodeId) ||
        !_readingSensors.add(nodeId)) return;
    final lifetime = _sensorLifetimes.putIfAbsent(nodeId, Object.new);
    bool active() => _canUpdate(nodeId) && identical(_sensorLifetimes[nodeId], lifetime);
    final versions = <String, Map<SensorMetric, int>>{
      for (final entry in _sensorObservations.entries)
        if (entry.key.startsWith('$nodeId:')) entry.key: entry.value.readVersion(),
    };
    try {
      final readings = await (controller as SensorMeasurementController)
          .readSensorMeasurements(nodeId).timeout(_readTimeout);
      if (!active()) return;
      final current = _devices.firstWhere((device) => device.nodeId == nodeId);
      final updated = current.copyWith(sensorCapabilities:
          readings.map((endpoint, reading) => MapEntry(endpoint, reading.supported)));
      setState(() {
        _devices = _devices.map((device) => device.nodeId == nodeId ? updated : device).toList();
        _sensorObservations.removeWhere((key, _) => key.startsWith('$nodeId:') &&
            !readings.containsKey(int.parse(key.split(':').last)));
        for (final entry in readings.entries) {
          final key = _stateKey(nodeId, entry.key);
          _sensorObservations.putIfAbsent(key, SensorObservation.new)
              .read(entry.value, versions[key] ?? const <SensorMetric, int>{}, DateTime.now());
        }
        if (current.onOffEndpoints.isEmpty && readings.isNotEmpty) {
          _unavailableNodes.remove(nodeId);
          _deviceErrors.remove(nodeId);
        }
      });
      if (readings.isNotEmpty) {
        _sensorFreshnessTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
          if (mounted && _sensorObservations.isNotEmpty) setState(() {});
        });
      }
      if (!_editingMetadata) {
        setState(() => _editingMetadata = true);
        try { await widget.deviceStore.save(updated); }
        catch (_) { /* A metadata save failure must not discard a live sensor read. */ }
        finally { if (mounted) setState(() => _editingMetadata = false); }
      }
    } catch (_) {
      if (active()) setState(() {
        final device = _devices.firstWhere((item) => item.nodeId == nodeId);
        _markSensorsStale(device);
        if (device.onOffEndpoints.isEmpty && device.sensorCapabilities.isNotEmpty) {
          _unavailableNodes.add(nodeId);
          _deviceErrors[nodeId] = 'Sensor read failed';
        }
      });
    } finally {
      if (identical(_sensorLifetimes[nodeId], lifetime)) _readingSensors.remove(nodeId);
    }
  }

  Future<void> _refreshOptionalControls(int nodeId) async {
    await _refreshSensors(nodeId);
    if (!_canUpdate(nodeId)) return;
    await _refreshColors(nodeId);
    if (_canUpdate(nodeId)) await _refreshDeviceCapabilities(nodeId);
  }

  Future<void> _refreshColors(int nodeId) async {
    final controller = widget.controller;
    if (controller is! ColorControlController || !_canUpdate(nodeId) ||
        !_readingColors.add(nodeId)) return;
    final lifetime = _colorLifetimes.putIfAbsent(nodeId, Object.new);
    final revisions = Map<String, int>.of(_colorRevisions);
    bool active() => _canUpdate(nodeId) && identical(_colorLifetimes[nodeId], lifetime);
    try {
      final values = await (controller as ColorControlController).readColors(nodeId).timeout(_readTimeout);
      if (!active()) return;
      final current = _devices.firstWhere((item) => item.nodeId == nodeId);
      final updated = current.copyWith(colorCapabilities:
          values.map((endpoint, color) => MapEntry(endpoint, color.capabilities)));
      setState(() {
        _devices = _devices.map((item) => item.nodeId == nodeId ? updated : item).toList();
        _colors.removeWhere((key, _) => key.startsWith('$nodeId:') &&
          !values.containsKey(int.parse(key.split(':').last)));
        for (final entry in values.entries) {
          final key = _stateKey(nodeId, entry.key);
          if (_colorRevisions[key] == revisions[key]) _colors[key] = entry.value;
          _staleColors.remove(key);
        }
      });
      if (!_editingMetadata) {
        setState(() => _editingMetadata = true);
        try { await widget.deviceStore.save(updated); }
        catch (_) { /* Keep a successfully read color usable; retry metadata later. */ }
        finally { if (mounted) setState(() => _editingMetadata = false); }
      }
    } catch (_) {
      if (active()) setState(() {
        final device = _devices.firstWhere((item) => item.nodeId == nodeId);
        _staleColors.addAll(device.colorCapabilities.keys.map((e) => _stateKey(nodeId, e)));
      });
    } finally {
      if (identical(_colorLifetimes[nodeId], lifetime)) _readingColors.remove(nodeId);
    }
  }

  Future<void> _setColor(DirectMatterDevice device, int endpoint, HSVColor color) async {
    final controller = widget.controller;
    final key = _stateKey(device.nodeId, endpoint);
    final state = _colors[key];
    if (controller is! ColorControlController || state == null || !state.supportsColor ||
        !_canUpdate(device.nodeId) || _unavailableNodes.contains(device.nodeId) ||
        _staleColors.contains(key) || !_busy.add(key)) return;
    final lifetime = _colorLifetimes.putIfAbsent(device.nodeId, Object.new);
    bool active() => _canUpdate(device.nodeId) && identical(_colorLifetimes[device.nodeId], lifetime);
    setState(() => _colorRevisions[key] = (_colorRevisions[key] ?? 0) + 1);
    try {
      final xy = hsvToXy(color);
      final colorController = controller as ColorControlController;
      await colorController.setColor(nodeId: device.nodeId, endpoint: endpoint,
        mode: state.supportsHueSaturation ? 'hs' : 'xy',
        first: state.supportsHueSaturation ? (color.hue % 360 / 360 * 254).round() : xy.x,
        second: state.supportsHueSaturation ? (color.saturation * 254).round() : xy.y,
      ).timeout(_readTimeout);
      if (!active()) return;
      final revision = _colorRevisions[key];
      final confirmation = await colorController.readColors(device.nodeId).timeout(_readTimeout);
      if (!active()) return;
      final confirmed = confirmation[endpoint];
      if (confirmed == null || confirmed.hsv == null) throw StateError('color not confirmed');
      setState(() {
        if (_colorRevisions[key] == revision) _colors[key] = confirmed;
        _colorRevisions[key] = (_colorRevisions[key] ?? 0) + 1;
        _staleColors.remove(key);
        _deviceErrors.remove(device.nodeId);
      });
    } catch (_) {
      if (active()) setState(() {
        _staleColors.add(key);
        _deviceErrors[device.nodeId] = 'Color command failed';
      });
    } finally {
      if (active()) setState(() => _busy.remove(key));
    }
  }

  Future<void> _renameChannel(DirectMatterDevice device, int endpoint) async {
    if (_editingMetadata || !_canUpdate(device.nodeId) || _removingNodes.isNotEmpty) return;
    final index = device.onOffEndpoints.indexOf(endpoint);
    setState(() => _editingMetadata = true);
    try {
      await showDialog<void>(context: context, barrierDismissible: false,
        builder: (_) => _RenameDeviceDialog(
          title: 'تغییر نام خروجی', emptyMessage: 'یک نام برای خروجی بنویس.',
          initialName: device.channelName(endpoint, index < 0 ? 0 : index),
          onSave: (name) async {
            if (!_canUpdate(device.nodeId)) throw StateError('device removed');
            final current = _devices.firstWhere((item) => item.nodeId == device.nodeId);
            final updated = current.copyWith(channelNames: <int,String>{...current.channelNames, endpoint: name});
            await widget.deviceStore.save(updated);
            if (!_canUpdate(device.nodeId)) return;
            setState(() => _devices = _devices.map((item) => item.nodeId == device.nodeId ? updated : item).toList());
          },
        ));
    } finally { if (mounted) setState(() => _editingMetadata = false); }
  }

  Future<void> _refreshDeviceCapabilities(int nodeId) async {
    final controller = widget.controller;
    if (!_readingCapabilities.add(nodeId)) return;
    try {
      Map<int, List<int>>? types;
      Map<int, int?>? levels;
      Map<int, DirectElectricalMeasurement>? measurements;
      if (controller is DeviceTypeReader) {
        try {
          types = await (controller as DeviceTypeReader)
              .readDeviceTypes(nodeId)
              .timeout(_readTimeout);
        } catch (_) {
          // Type labels are optional and do not gate controls.
        }
      }
      if (controller is LevelControlController) {
        try {
          levels = await (controller as LevelControlController)
              .readLevels(nodeId)
              .timeout(_readTimeout);
        } catch (_) {
          // Preserve cached capability and existing state on an optional read failure.
        }
      }
      if (controller is ElectricalMeasurementController) {
        try {
          measurements =
              await (controller as ElectricalMeasurementController)
                  .readElectricalMeasurements(nodeId)
                  .timeout(_readTimeout);
        } catch (_) {
          if (_canUpdate(nodeId)) {
            setState(() {
              final device = _devices.firstWhere((item) => item.nodeId == nodeId);
              for (final entry in device.measurementCapabilities.entries) {
                _staleElectricalMetrics[_stateKey(nodeId, entry.key)] =
                    Set<ElectricalMetric>.of(entry.value);
              }
            });
          }
        }
      }
      if ((types == null || types.isEmpty) &&
          levels == null &&
          measurements == null) {
        return;
      }
      if (!_canUpdate(nodeId) || _editingMetadata) return;
      // Product metadata failures must never disable a working OnOff control.
      setState(() => _editingMetadata = true);
      try {
        final current = _devices.firstWhere((device) => device.nodeId == nodeId);
        final updated = current.copyWith(
          deviceTypes: types == null || types.isEmpty ? null : types,
          levelEndpoints: levels?.keys.toList(growable: false),
          measurementCapabilities: measurements?.map(
            (endpoint, value) => MapEntry(endpoint, value.supported),
          ),
        );
        await widget.deviceStore.save(updated);
        if (!_canUpdate(nodeId)) return;
        setState(() {
          _devices = _devices
              .map((device) => device.nodeId == nodeId ? updated : device)
              .toList();
          if (levels != null) {
            for (final entry in levels.entries) {
              final key = _stateKey(nodeId, entry.key);
              if (entry.value == null) {
                _levels.remove(key);
              } else {
                _levels[key] = entry.value!;
              }
            }
          }
          if (measurements != null) {
            _electricalMeasurements.removeWhere(
              (key, _) => key.startsWith('$nodeId:'),
            );
            for (final entry in measurements.entries) {
              _electricalMeasurements[_stateKey(nodeId, entry.key)] =
                  entry.value;
            }
            _staleElectricalMetrics.removeWhere((key, _) => key.startsWith('$nodeId:'));
          }
        });
      } finally {
        if (mounted) setState(() => _editingMetadata = false);
      }
    } catch (_) {
      // Preserve previously read metadata; the next successful refresh retries.
    } finally {
      _readingCapabilities.remove(nodeId);
    }
  }

  Future<void> _retryConnections() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _refreshAllStates();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  bool _sameEndpoints(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<void> _addDevice() async {
    if (_editingMetadata) return;
    final device = await Navigator.of(context).push<DirectMatterDevice>(
      MaterialPageRoute<DirectMatterDevice>(
        builder: (_) => DirectMatterAddDeviceScreen(
          controller: widget.controller,
          deviceStore: widget.deviceStore,
        ),
      ),
    );
    if (device == null || !mounted) return;
    setState(() {
      _devices = <DirectMatterDevice>[
        ..._devices.where((item) => item.nodeId != device.nodeId),
        device,
      ];
      _unavailableNodes.remove(device.nodeId);
      _deviceErrors.remove(device.nodeId);
    });
    await _refreshAllStates();
  }

  Future<void> _setOnOff(
    DirectMatterDevice device,
    int endpoint,
    bool value,
  ) async {
    final key = _stateKey(device.nodeId, endpoint);
    if (_busy.contains(key) || !_canUpdate(device.nodeId)) return;
    setState(() {
      _busy.add(key);
      _deviceErrors.remove(device.nodeId);
    });
    try {
      await widget.controller
          .setOnOff(nodeId: device.nodeId, endpoint: endpoint, value: value)
          .timeout(_readTimeout);
      final confirmed = await widget.controller
          .readOnOff(nodeId: device.nodeId, endpoint: endpoint)
          .timeout(_readTimeout);
      if (_canUpdate(device.nodeId)) {
        setState(() {
          _states[key] = confirmed;
          _unavailableNodes.remove(device.nodeId);
          _deviceErrors.remove(device.nodeId);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _unavailableNodes.add(device.nodeId);
          _deviceErrors[device.nodeId] = 'Command failed: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(key));
      }
    }
  }

  Future<void> _setLevel(DirectMatterDevice device, int endpoint, int level) async {
    final controller = widget.controller;
    final key = _stateKey(device.nodeId, endpoint);
    if (controller is! LevelControlController ||
        _busy.contains(key) || !_canUpdate(device.nodeId)) return;
    final levelController = controller as LevelControlController;
    final requested = level.clamp(1, 254);
    setState(() {
      _busy.add(key);
      _deviceErrors.remove(device.nodeId);
    });
    try {
      await levelController
          .setLevel(nodeId: device.nodeId, endpoint: endpoint, level: requested)
          .timeout(_readTimeout);
      final levels = await levelController.readLevels(device.nodeId).timeout(_readTimeout);
      final confirmed = levels[endpoint];
      if (confirmed == null) {
        throw const FormatException('LevelControl state was not returned');
      }
      final confirmedOnOff = await widget.controller
          .readOnOff(nodeId: device.nodeId, endpoint: endpoint)
          .timeout(_readTimeout);
      if (_canUpdate(device.nodeId)) {
        setState(() {
          _levels[key] = confirmed;
          _states[key] = confirmedOnOff;
          _unavailableNodes.remove(device.nodeId);
          _deviceErrors.remove(device.nodeId);
        });
      }
    } catch (error) {
      if (_canUpdate(device.nodeId)) {
        setState(() {
          _deviceErrors[device.nodeId] = 'Level command failed: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _manageChannels(DirectMatterDevice device) async {
    if (_editingMetadata ||
        _removingNodes.isNotEmpty ||
        !_canUpdate(device.nodeId))
      return;
    setState(() => _editingMetadata = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ChannelNamesDialog(
          device: device,
          onTest: (endpoint) async {
            final state = _states[_stateKey(device.nodeId, endpoint)];
            if (state == null) return;
            await _setOnOff(device, endpoint, !state);
          },
          canTest: (endpoint) =>
              !_unavailableNodes.contains(device.nodeId) &&
              _states[_stateKey(device.nodeId, endpoint)] != null &&
              !_busy.contains(_stateKey(device.nodeId, endpoint)),
          onSave: (names) async {
            final index = _devices.indexWhere(
              (item) => item.nodeId == device.nodeId,
            );
            if (index < 0) return;
            final updated = _devices[index].copyWith(channelNames: names);
            await widget.deviceStore.save(updated);
            if (!mounted) return;
            setState(() {
              final devices = List<DirectMatterDevice>.of(_devices);
              devices[index] = updated;
              _devices = devices;
            });
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _editingMetadata = false);
    }
  }

  Future<void> _renameDevice(DirectMatterDevice device) async {
    if (_editingMetadata ||
        _removingNodes.isNotEmpty ||
        !_canUpdate(device.nodeId))
      return;
    setState(() => _editingMetadata = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RenameDeviceDialog(
          initialName: device.name,
          onSave: (name) async {
            final current = _devices.firstWhere(
              (item) => item.nodeId == device.nodeId,
            );
            await widget.deviceStore.save(current.copyWith(name: name));
            if (!mounted) return;
            setState(() {
              _devices = _devices
                  .map(
                    (item) => item.nodeId == device.nodeId
                        ? item.copyWith(name: name)
                        : item,
                  )
                  .toList(growable: false);
            });
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _editingMetadata = false);
    }
  }

  void _showMetadataError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تغییرات ذخیره نشد. دوباره تلاش کن.')),
    );
  }

  Future<void> _renameHome() async {
    if (_editingMetadata) return;
    setState(() => _editingMetadata = true);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _HomeNameDialog(initialName: _homeProfile.name),
      );
      if (name == null || !mounted) return;
      final next = _homeProfile.rename(name);
      await widget.homeStore.save(next);
      if (mounted) setState(() => _homeProfile = next);
    } catch (_) {
      _showMetadataError();
    } finally {
      if (mounted) setState(() => _editingMetadata = false);
    }
  }

  Future<void> _moveRoom(ManisaRoom room, int offset) async {
    if (_editingMetadata) return;
    final next = _roomCatalog.moveRoom(room.id, offset);
    if (identical(next, _roomCatalog)) return;
    setState(() => _editingMetadata = true);
    try {
      await widget.roomStore.save(next);
      if (mounted) setState(() => _roomCatalog = next);
    } catch (_) {
      _showMetadataError();
    } finally {
      if (mounted) setState(() => _editingMetadata = false);
    }
  }

  Future<ManisaRoom?> _createRoom() async {
    if (_editingMetadata) return null;
    setState(() => _editingMetadata = true);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _RoomNameDialog(
          title: 'اتاق جدید',
          actionLabel: 'ساخت اتاق',
          reservedNames: _roomCatalog.rooms.map((room) => room.name).toSet(),
        ),
      );
      if (name == null || !mounted) return null;
      final room = ManisaRoom(
        id: 'room-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        name: name,
      );
      final next = _roomCatalog.addRoom(room);
      await widget.roomStore.save(next);
      if (!mounted) return null;
      setState(() => _roomCatalog = next);
      return room;
    } catch (_) {
      _showMetadataError();
      return null;
    } finally {
      if (mounted) setState(() => _editingMetadata = false);
    }
  }

  Future<void> _renameRoom(ManisaRoom room) async {
    if (_editingMetadata) return;
    setState(() => _editingMetadata = true);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _RoomNameDialog(
          title: 'تغییر نام اتاق',
          actionLabel: 'ذخیره',
          initialName: room.name,
          reservedNames: _roomCatalog.rooms
              .where((item) => item.id != room.id)
              .map((item) => item.name)
              .toSet(),
        ),
      );
      if (name == null || !mounted) return;
      final next = _roomCatalog.renameRoom(room.id, name);
      await widget.roomStore.save(next);
      if (mounted) setState(() => _roomCatalog = next);
    } catch (_) {
      _showMetadataError();
    } finally {
      if (mounted) setState(() => _editingMetadata = false);
    }
  }

  Future<void> _deleteRoom(ManisaRoom room) async {
    if (_editingMetadata) return;
    final assignedCount = _devices
        .where(
          (device) => _roomCatalog.roomIdForDevice(device.nodeId) == room.id,
        )
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف اتاق؟'),
        content: Text(
          assignedCount == 0
              ? 'اتاق «${room.name}» حذف شود؟'
              : 'اتاق «${room.name}» حذف شود؟ ${toPersianDigits(assignedCount)} وسیله به بخش «بدون اتاق» منتقل می‌شود.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف اتاق'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _editingMetadata = true);
    try {
      final next = _roomCatalog.removeRoom(room.id);
      await widget.roomStore.save(next);
      if (mounted) setState(() => _roomCatalog = next);
    } catch (_) {
      _showMetadataError();
    } finally {
      if (mounted) setState(() => _editingMetadata = false);
    }
  }

  Future<void> _assignRoom(DirectMatterDevice device) async {
    if (_editingMetadata) return;
    String? roomId;
    if (_roomCatalog.rooms.isEmpty) {
      final created = await _createRoom();
      if (created == null) return;
      roomId = created.id;
    } else {
      const unassigned = '__unassigned__';
      final current = _roomCatalog.roomIdForDevice(device.nodeId);
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('اتاق «${device.name}»'),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(unassigned),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_outlined),
                title: const Text('بدون اتاق'),
                trailing: current == null ? const Icon(Icons.check) : null,
              ),
            ),
            for (final room in _roomCatalog.rooms)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(room.id),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.meeting_room_outlined),
                  title: Text(room.name),
                  trailing: current == room.id ? const Icon(Icons.check) : null,
                ),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      roomId = selected == unassigned ? null : selected;
    }
    setState(() => _editingMetadata = true);
    try {
      final next = _roomCatalog.assignDevice(device.nodeId, roomId);
      await widget.roomStore.save(next);
      if (mounted) setState(() => _roomCatalog = next);
    } catch (_) {
      _showMetadataError();
    } finally {
      if (mounted) setState(() => _editingMetadata = false);
    }
  }

  Future<void> _toggleFavorite(DirectMatterDevice device, int endpoint) async {
    if (_editingMetadata || !_canUpdate(device.nodeId)) return;
    setState(() => _editingMetadata = true);
    try {
      final next = _favorites.toggle(device.nodeId, endpoint);
      await widget.favoriteStore.save(next);
      if (mounted) setState(() => _favorites = next);
    } catch (_) {
      _showMetadataError();
    } finally {
      if (mounted) setState(() => _editingMetadata = false);
    }
  }

  Future<void> _removeDevice(DirectMatterDevice device) async {
    if (_editingMetadata) return;
    if (_removingNodes.contains(device.nodeId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف وسیله از مانیسا؟'),
        content: Text(
          '«${device.name}» از مانیسا حذف شود؟ برای افزودن دوباره، وسیله باید آمادهٔ اتصال باشد.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف وسیله'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _removingNodes.contains(device.nodeId))
      return;
    setState(() {
      _removingNodes.add(device.nodeId);
      _deviceErrors.remove(device.nodeId);
      for (final endpoint in device.onOffEndpoints) {
        _busy.add(_stateKey(device.nodeId, endpoint));
      }
    });
    try {
      // Only forget the device after the native RemoveCurrentFabric callback.
      await widget.controller
          .removeDevice(device.nodeId)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw TimeoutException(
              'Removal not confirmed; device kept in the list',
            ),
          );
      final nextRoomCatalog = _roomCatalog.assignDevice(device.nodeId, null);
      await widget.roomStore.save(nextRoomCatalog);
      await widget.deviceStore.remove(device.nodeId);
      final nextFavorites = _favorites.removeDevice(device.nodeId);
      try {
        await widget.favoriteStore.save(nextFavorites);
      } catch (_) {
        // A stale favorite is filtered on the next load and must not turn a
        // confirmed Matter removal into a false failure.
      }
      if (mounted) {
        setState(() {
          _roomCatalog = nextRoomCatalog;
          _favorites = nextFavorites;
          _devices = _devices
              .where((item) => item.nodeId != device.nodeId)
              .toList(growable: false);
          _unavailableNodes.remove(device.nodeId);
          _sensorLifetimes.remove(device.nodeId);
          _readingSensors.remove(device.nodeId);
          _sensorObservations.removeWhere((key, _) => key.startsWith('${device.nodeId}:'));
          if (_sensorObservations.isEmpty) {
            _sensorFreshnessTimer?.cancel();
            _sensorFreshnessTimer = null;
          }
          _colorLifetimes.remove(device.nodeId);
          _readingColors.remove(device.nodeId);
          _colors.removeWhere((key, _) => key.startsWith('${device.nodeId}:'));
          _colorRevisions.removeWhere((key, _) => key.startsWith('${device.nodeId}:'));
          _staleColors.removeWhere((key) => key.startsWith('${device.nodeId}:'));
          _deviceErrors.remove(device.nodeId);
          for (final endpoint in device.onOffEndpoints) {
            _states.remove(_stateKey(device.nodeId, endpoint));
          }
          _electricalMeasurements.removeWhere(
            (key, _) => key.startsWith('${device.nodeId}:'),
          );
          _staleElectricalMetrics.removeWhere(
            (key, _) => key.startsWith('${device.nodeId}:'),
          );
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _deviceErrors[device.nodeId] = 'Remove failed: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _removingNodes.remove(device.nodeId);
          for (final endpoint in device.onOffEndpoints) {
            _busy.remove(_stateKey(device.nodeId, endpoint));
          }
        });
      }
    }
  }

  List<Widget> _roomSections(BuildContext context) {
    final sections = <Widget>[];
    for (final room in _roomCatalog.rooms) {
      final devices = _devices
          .where(
            (device) => _roomCatalog.roomIdForDevice(device.nodeId) == room.id,
          )
          .toList(growable: false);
      sections.addAll(_roomSection(context, room: room, devices: devices));
    }
    final unassigned = _devices
        .where((device) => _roomCatalog.roomIdForDevice(device.nodeId) == null)
        .toList(growable: false);
    if (unassigned.isNotEmpty) {
      sections.addAll(
        _roomSection(context, title: 'بدون اتاق', devices: unassigned),
      );
    }
    return sections;
  }

  List<Widget> _favoriteSection(BuildContext context) {
    final resolved = <(FavoriteOutput, DirectMatterDevice, int)>[];
    for (final favorite in _favorites.outputs) {
      final deviceIndex = _devices.indexWhere(
        (device) => device.nodeId == favorite.nodeId,
      );
      if (deviceIndex < 0) continue;
      final device = _devices[deviceIndex];
      final outputIndex = device.onOffEndpoints.indexOf(favorite.endpoint);
      if (outputIndex < 0) continue;
      resolved.add((favorite, device, outputIndex));
    }
    if (resolved.isEmpty) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 16, 4, 8),
        child: Row(
          children: <Widget>[
            const Icon(Icons.star_rounded, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'علاقه‌مندی‌ها',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text('${toPersianDigits(resolved.length)} خروجی'),
          ],
        ),
      ),
      Card(
        child: Column(
          children: <Widget>[
            for (final item in resolved)
              _FavoriteOutputTile(
                device: item.$2,
                endpoint: item.$1.endpoint,
                outputIndex: item.$3,
                roomName: _roomNameForDevice(item.$2.nodeId),
                state: _states[_stateKey(item.$2.nodeId, item.$1.endpoint)],
                busy: _busy.contains(
                  _stateKey(item.$2.nodeId, item.$1.endpoint),
                ),
                unavailable: _unavailableNodes.contains(item.$2.nodeId),
                onChanged: (value) =>
                    _setOnOff(item.$2, item.$1.endpoint, value),
                onRemove: () => _toggleFavorite(item.$2, item.$1.endpoint),
                onRefresh: () => _refreshDevice(item.$2),
              ),
          ],
        ),
      ),
    ];
  }

  String? _roomNameForDevice(int nodeId) {
    final roomId = _roomCatalog.roomIdForDevice(nodeId);
    if (roomId == null) return null;
    for (final room in _roomCatalog.rooms) {
      if (room.id == roomId) return room.name;
    }
    return null;
  }

  List<Widget> _roomSection(
    BuildContext context, {
    ManisaRoom? room,
    String? title,
    required List<DirectMatterDevice> devices,
  }) {
    final roomIndex = room == null ? -1 : _roomCatalog.rooms.indexOf(room);
    return <Widget>[
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 16, 4, 8),
        child: Row(
          children: <Widget>[
            const Icon(Icons.meeting_room_outlined, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                room?.name ?? title!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text('${toPersianDigits(devices.length)} وسیله'),
            if (room != null)
              PopupMenuButton<String>(
                tooltip: 'تنظیمات اتاق',
                onSelected: (value) {
                  if (value == 'rename') _renameRoom(room);
                  if (value == 'up') _moveRoom(room, -1);
                  if (value == 'down') _moveRoom(room, 1);
                  if (value == 'delete') _deleteRoom(room);
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('تغییر نام اتاق'),
                  ),
                  PopupMenuItem(
                    value: 'up',
                    enabled: roomIndex > 0,
                    child: const Text('انتقال به بالا'),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled:
                        roomIndex >= 0 &&
                        roomIndex < _roomCatalog.rooms.length - 1,
                    child: const Text('انتقال به پایین'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'delete', child: Text('حذف اتاق')),
                ],
              ),
          ],
        ),
      ),
      if (devices.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.devices_other_outlined),
            title: Text('هنوز وسیله‌ای در این اتاق نیست'),
          ),
        ),
      for (final device in devices)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _DirectMatterDeviceCard(
            device: device,
            roomName: room?.name,
            states: _states,
            levels: _levels,
            colors: _colors,
            staleColors: _staleColors,
            onColorChanged: (endpoint, color) => _setColor(device, endpoint, color),
            onRenameChannel: (endpoint) => _renameChannel(device, endpoint),
            electricalMeasurements: _electricalMeasurements,
            sensorObservations: _sensorObservations,
            powerController: widget.controller is PowerSourceController
                ? widget.controller as PowerSourceController : null,
            staleElectricalMetrics: _staleElectricalMetrics,
            busy: _busy,
            error: _deviceErrors[device.nodeId],
            unavailable: _unavailableNodes.contains(device.nodeId),
            favorites: _favorites,
            onChanged: (endpoint, value) => _setOnOff(device, endpoint, value),
            onLevelChanged: (endpoint, level) => _setLevel(device, endpoint, level),
            onRemove: () => _removeDevice(device),
            onRename: () => _renameDevice(device),
            onAssignRoom: () => _assignRoom(device),
            onManageChannels: () => _manageChannels(device),
            onRefresh: () => _refreshDevice(device),
            onToggleFavorite: (endpoint) => _toggleFavorite(device, endpoint),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مانیسا'),
        actions: <Widget>[
          IconButton(
            tooltip: 'افزودن اتاق',
            onPressed: _loading || _editingMetadata ? null : _createRoom,
            icon: const Icon(Icons.add_home_outlined),
          ),
          IconButton(
            tooltip: 'بررسی وضعیت',
            onPressed: _loading ? null : _refreshAllStates,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addDevice,
        icon: const Icon(Icons.add),
        label: const Text('افزودن وسیله'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAllStates,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _homeProfile.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'تغییر نام خانه',
                        onPressed: _editingMetadata ? null : _renameHome,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'وسایل خانه را از همین‌جا کنترل کن',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 16),
                    MaterialBanner(
                      content: _MatterErrorNotice(error: _error!),
                      actions: <Widget>[
                        TextButton(
                          onPressed: _retrying ? null : _retryConnections,
                          child: Text(
                            _retrying ? 'در حال بررسی…' : 'تلاش دوباره',
                          ),
                        ),
                        TextButton(
                          onPressed: _retrying
                              ? null
                              : () => setState(() => _error = null),
                          child: const Text('بستن'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_favorites.outputs.isNotEmpty)
                    ..._favoriteSection(context),
                  if (_devices.isEmpty && _roomCatalog.rooms.isEmpty)
                    const _EmptyDirectMatterState(),
                  if (_devices.isNotEmpty || _roomCatalog.rooms.isNotEmpty)
                    ..._roomSections(context),
                ],
              ),
            ),
    );
  }
}

final class _EmptyDirectMatterState extends StatelessWidget {
  const _EmptyDirectMatterState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: <Widget>[
            const Icon(Icons.lightbulb_outline, size: 52),
            const SizedBox(height: 16),
            Text(
              'اولین وسیله را اضافه کن',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'کد روی وسیله را اسکن کن؛ مرحله‌به‌مرحله برای اتصال راهنمایی‌ات می‌کنیم.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

final class _DirectMatterDeviceCard extends StatelessWidget {
  const _DirectMatterDeviceCard({
    required this.device,
    required this.roomName,
    required this.states,
    required this.levels,
    required this.colors,
    required this.staleColors,
    required this.onColorChanged,
    required this.onRenameChannel,
    required this.electricalMeasurements,
    required this.sensorObservations,
    required this.powerController,
    required this.staleElectricalMetrics,
    required this.busy,
    required this.error,
    required this.unavailable,
    required this.favorites,
    required this.onChanged,
    required this.onLevelChanged,
    required this.onRemove,
    required this.onRename,
    required this.onAssignRoom,
    required this.onManageChannels,
    required this.onRefresh,
    required this.onToggleFavorite,
  });

  final DirectMatterDevice device;
  final String? roomName;
  final Map<String, bool> states;
  final Map<String, int> levels;
  final Map<String, DirectColorState> colors;
  final Set<String> staleColors;
  final void Function(int endpoint, HSVColor color) onColorChanged;
  final ValueChanged<int> onRenameChannel;
  final Map<String, DirectElectricalMeasurement> electricalMeasurements;
  final Map<String, SensorObservation> sensorObservations;
  final PowerSourceController? powerController;
  final Map<String, Set<ElectricalMetric>> staleElectricalMetrics;
  final Set<String> busy;
  final String? error;
  final bool unavailable;
  final FavoriteCatalog favorites;
  final void Function(int endpoint, bool value) onChanged;
  final void Function(int endpoint, int level) onLevelChanged;
  final VoidCallback onRemove;
  final VoidCallback onRename;
  final VoidCallback onAssignRoom;
  final VoidCallback onManageChannels;
  final VoidCallback onRefresh;
  final void Function(int endpoint) onToggleFavorite;

  String _key(int endpoint) => '${device.nodeId}:$endpoint';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        device.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(device.productLabel),
                      Text(
                        device.onOffEndpoints.isEmpty && device.sensorCapabilities.isNotEmpty
                            ? (roomName ?? 'بدون اتاق')
                            : roomName == null
                                ? '${toPersianDigits(device.onOffEndpoints.length)} خروجی'
                                : '${toPersianDigits(device.onOffEndpoints.length)} خروجی · $roomName',
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'تنظیمات وسیله',
                  onSelected: (value) {
                    if (value == 'remove') onRemove();
                    if (value == 'rename') onRename();
                    if (value == 'room') onAssignRoom();
                    if (value == 'channels') onManageChannels();
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('تغییر نام وسیله'),
                    ),
                    PopupMenuItem(value: 'room', child: Text('تغییر اتاق')),
                    if (device.onOffEndpoints.isNotEmpty) const PopupMenuItem(
                      value: 'channels',
                      child: Text('نام خروجی‌ها'),
                    ),
                    PopupMenuItem(value: 'remove', child: Text('حذف وسیله')),
                  ],
                ),
              ],
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: _MatterErrorNotice(error: error!)),
                      TextButton(
                        onPressed: onRefresh,
                        child: const Text('تلاش دوباره'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (device.onOffEndpoints.isEmpty && device.sensorCapabilities.isEmpty)
              TextButton(
                onPressed: onRefresh,
                child: const Text('دریافت کنترل‌های وسیله'),
              ),
            for (var index = 0; index < device.onOffEndpoints.length; index++)
              Builder(
                builder: (context) {
                  final endpoint = device.onOffEndpoints[index];
                  final key = _key(endpoint);
                  final state = states[key];
                  final level = levels[key];
                  final measurement = electricalMeasurements[key];
                  final isBusy = busy.contains(key);
                  final favorite = favorites.contains(device.nodeId, endpoint);
                  if (state == null) {
                    return Column(
                      children: <Widget>[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            device.channelName(endpoint, index),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: const Text('وضعیت دریافت نشده'),
                          leading: IconButton(
                            tooltip: favorite
                                ? 'حذف از علاقه‌مندی‌ها'
                                : 'افزودن به علاقه‌مندی‌ها',
                            onPressed: () => onToggleFavorite(endpoint),
                            icon: Icon(
                              favorite ? Icons.star_rounded : Icons.star_border,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: isBusy ? null : onRefresh,
                            child: const Text('بررسی'),
                          ),
                        ),
                        Align(alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: ValueKey('rename-output-${device.nodeId}-$endpoint'),
                            onPressed: () => onRenameChannel(endpoint),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('تغییر نام خروجی'),
                          )),
                        if (device.colorCapabilities.containsKey(endpoint))
                          ColorControl(key: ValueKey('color-${device.nodeId}-$endpoint'),
                            state: colors[key], enabled: !isBusy && !unavailable,
                            stale: staleColors.contains(key) || unavailable,
                            onRefresh: onRefresh,
                            onChanged: (color) => onColorChanged(endpoint, color)),
                      if (device.levelEndpoints.contains(endpoint))
                          _LevelControl(
                            level: level,
                            enabled: false,
                            onChanged: (value) => onLevelChanged(endpoint, value),
                          ),
                        if (device.measurementCapabilities.containsKey(endpoint))
                          _ElectricalMeasurementPanel(
                            supported:
                                device.measurementCapabilities[endpoint]!,
                            measurement: measurement,
                            staleMetrics: unavailable
                                ? device.measurementCapabilities[endpoint]!
                                : staleElectricalMetrics[key] ?? const {},
                          ),
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          device.channelName(endpoint, index),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          unavailable
                              ? 'در دسترس نیست · آخرین وضعیت: ${state ? 'روشن' : 'خاموش'}'
                              : isBusy
                              ? 'در حال انجام…'
                              : state
                              ? (device.isSocket(endpoint) ? 'برق وصل است' : 'روشن')
                              : (device.isSocket(endpoint) ? 'برق قطع است' : 'خاموش'),
                        ),
                        value: state,
                        onChanged: isBusy || unavailable
                            ? null
                            : (next) => onChanged(endpoint, next),
                        secondary: IconButton(
                          tooltip: favorite
                              ? 'حذف از علاقه‌مندی‌ها'
                              : 'افزودن به علاقه‌مندی‌ها',
                          onPressed: () => onToggleFavorite(endpoint),
                          icon: isBusy
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  favorite ? Icons.star_rounded : Icons.star_border,
                                ),
                            ),
                        ),
                        Align(alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: ValueKey('rename-output-${device.nodeId}-$endpoint'),
                            onPressed: () => onRenameChannel(endpoint),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('تغییر نام خروجی'),
                          )),
                        if (device.colorCapabilities.containsKey(endpoint))
                          ColorControl(key: ValueKey('color-${device.nodeId}-$endpoint'),
                            state: colors[key], enabled: !isBusy && !unavailable,
                            stale: staleColors.contains(key) || unavailable,
                            onRefresh: onRefresh,
                            onChanged: (color) => onColorChanged(endpoint, color)),
                      if (device.levelEndpoints.contains(endpoint))
                        _LevelControl(
                          level: level,
                          enabled: !isBusy && !unavailable && level != null,
                          onChanged: (value) => onLevelChanged(endpoint, value),
                        ),
                      if (device.measurementCapabilities.containsKey(endpoint))
                        _ElectricalMeasurementPanel(
                          supported: device.measurementCapabilities[endpoint]!,
                          measurement: measurement,
                          staleMetrics: unavailable
                              ? device.measurementCapabilities[endpoint]!
                              : staleElectricalMetrics[key] ?? const {},
                        ),
                    ],
                  );
                },
              ),
            for (final endpoint in device.colorCapabilities.keys)
              if (!device.onOffEndpoints.contains(endpoint)) ...<Widget>[
                ListTile(title: Text(device.channelName(endpoint,
                    device.colorCapabilities.keys.toList().indexOf(endpoint))),
                  trailing: IconButton(tooltip: 'تغییر نام خروجی', icon: const Icon(Icons.edit_outlined),
                    onPressed: () => onRenameChannel(endpoint))),
                ColorControl(key: ValueKey('color-${device.nodeId}-$endpoint'),
                  state: colors[_key(endpoint)], enabled: !busy.contains(_key(endpoint)) && !unavailable,
                  stale: staleColors.contains(_key(endpoint)) || unavailable,
                  onRefresh: onRefresh, onChanged: (color) => onColorChanged(endpoint, color)),
                if (device.levelEndpoints.contains(endpoint)) _LevelControl(
                  level: levels[_key(endpoint)], enabled: !busy.contains(_key(endpoint)) && !unavailable,
                  onChanged: (value) => onLevelChanged(endpoint, value)),
              ],
            if (powerController != null)
              PowerSourcePanel(key: ValueKey('power-${device.nodeId}'),
                nodeId: device.nodeId, controller: powerController!),
            for (final entry in device.sensorCapabilities.entries)
              SensorMeasurementPanel(
                key: ValueKey('sensors-${device.nodeId}-${entry.key}'),
                supported: entry.value, observation: sensorObservations[_key(entry.key)],
                now: DateTime.now(), onRefresh: onRefresh,
                title: device.channelNames[entry.key] ?? (device.sensorCapabilities.length > 1
                    ? 'سنسور ${toPersianDigits(device.sensorCapabilities.keys.toList().indexOf(entry.key)+1)}' : null),
              ),
            for (final entry in device.measurementCapabilities.entries)
              if (!device.onOffEndpoints.contains(entry.key))
                _ElectricalMeasurementPanel(
                  title: device.measurementCapabilities.length == 1
                      ? 'اندازه‌گیری وسیله'
                      : 'اندازه‌گیری ${toPersianDigits(
                          device.measurementCapabilities.keys
                                  .toList(growable: false)
                                  .indexOf(entry.key) +
                              1,
                        )}',
                  supported: entry.value,
                  measurement: electricalMeasurements[_key(entry.key)],
                  staleMetrics: unavailable
                      ? entry.value
                      : staleElectricalMetrics[_key(entry.key)] ?? const {},
                ),
          ],
        ),
      ),
    );
  }
}

final class _ElectricalMeasurementPanel extends StatelessWidget {
  const _ElectricalMeasurementPanel({
    required this.supported,
    required this.measurement,
    required this.staleMetrics,
    this.title = 'مصرف برق',
  });

  final Set<ElectricalMetric> supported;
  final DirectElectricalMeasurement? measurement;
  final Set<ElectricalMetric> staleMetrics;
  final String title;

  String _value(ElectricalMetric metric) {
    final current = measurement;
    if (current == null) return 'دریافت نشده';
    switch (metric) {
      case ElectricalMetric.activePower:
        final value = current.activePowerMilliwatts;
        return value == null ? 'دریافت نشده' : formatActivePower(value);
      case ElectricalMetric.voltage:
        final value = current.voltageMillivolts;
        return value == null ? 'دریافت نشده' : formatVoltage(value);
      case ElectricalMetric.activeCurrent:
        final value = current.activeCurrentMilliamps;
        return value == null ? 'دریافت نشده' : formatActiveCurrent(value);
      case ElectricalMetric.cumulativeEnergyImported:
        final value = current.cumulativeEnergyImportedMilliwattHours;
        return value == null ? 'دریافت نشده' : formatImportedEnergy(value);
    }
  }

  String _label(ElectricalMetric metric) {
    switch (metric) {
      case ElectricalMetric.activePower:
        return 'توان فعلی';
      case ElectricalMetric.voltage:
        return 'ولتاژ';
      case ElectricalMetric.activeCurrent:
        return 'جریان';
      case ElectricalMetric.cumulativeEnergyImported:
        return 'انرژی مصرف‌شده';
    }
  }

  @override
  Widget build(BuildContext context) {
    const order = <ElectricalMetric>[
      ElectricalMetric.activePower,
      ElectricalMetric.cumulativeEnergyImported,
      ElectricalMetric.voltage,
      ElectricalMetric.activeCurrent,
    ];
    final visible = order.where(supported.contains).toList(growable: false);
    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.bolt_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (staleMetrics.isNotEmpty)
                Text(
                  'نیاز به به‌روزرسانی',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final metric in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(_label(metric))),
                  if (staleMetrics.contains(metric)) ...<Widget>[
                    Icon(Icons.sync_problem_outlined, size: 16,
                      color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    _value(metric),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

final class _LevelControl extends StatefulWidget {
  const _LevelControl({
    required this.level,
    required this.enabled,
    required this.onChanged,
  });

  final int? level;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_LevelControl> createState() => _LevelControlState();
}

final class _LevelControlState extends State<_LevelControl> {
  double? _preview;

  @override
  void didUpdateWidget(_LevelControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level || !widget.enabled) _preview = null;
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    if (level == null) {
      return const Padding(
        padding: EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('شدت نور دریافت نشده'),
        ),
      );
    }
    final confirmed = matterLevelToPercent(level).toDouble();
    final value = (_preview ?? confirmed).clamp(1, 100).toDouble();
    final label = '${toPersianDigits(value.round())}٪';
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8, end: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 8),
            child: Row(
              children: <Widget>[
                const Expanded(child: Text('شدت نور')),
                Text(label),
              ],
            ),
          ),
          Slider(
            value: value,
            min: 1,
            max: 100,
            divisions: 99,
            label: label,
            semanticFormatterCallback: (sliderValue) =>
                '${toPersianDigits(sliderValue.round())} درصد',
            onChanged: widget.enabled
                ? (next) => setState(() => _preview = next)
                : null,
            // One Matter command is sent when the gesture ends, rather than
            // flooding a constrained device for every rendered slider frame.
            onChangeEnd: widget.enabled
                ? (next) {
                    setState(() => _preview = null);
                    widget.onChanged(percentToMatterLevel(next.round()));
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

final class _FavoriteOutputTile extends StatelessWidget {
  const _FavoriteOutputTile({
    required this.device,
    required this.endpoint,
    required this.outputIndex,
    required this.roomName,
    required this.state,
    required this.busy,
    required this.unavailable,
    required this.onChanged,
    required this.onRemove,
    required this.onRefresh,
  });

  final DirectMatterDevice device;
  final int endpoint;
  final int outputIndex;
  final String? roomName;
  final bool? state;
  final bool busy;
  final bool unavailable;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final subtitlePrefix = roomName == null
        ? device.name
        : '${device.name} · $roomName';
    final value = state;
    if (value == null) {
      return ListTile(
        title: Text(device.channelName(endpoint, outputIndex)),
        subtitle: Text('$subtitlePrefix · وضعیت دریافت نشده'),
        leading: IconButton(
          tooltip: 'حذف از علاقه‌مندی‌ها',
          onPressed: onRemove,
          icon: const Icon(Icons.star_rounded),
        ),
        trailing: TextButton(
          onPressed: busy ? null : onRefresh,
          child: const Text('بررسی'),
        ),
      );
    }
    return SwitchListTile.adaptive(
      title: Text(device.channelName(endpoint, outputIndex)),
      subtitle: Text(
        unavailable
            ? '$subtitlePrefix · در دسترس نیست؛ آخرین وضعیت: ${value ? 'روشن' : 'خاموش'}'
            : '$subtitlePrefix · ${value ? 'روشن' : 'خاموش'}',
      ),
      value: value,
      onChanged: busy || unavailable ? null : onChanged,
      secondary: IconButton(
        tooltip: 'حذف از علاقه‌مندی‌ها',
        onPressed: onRemove,
        icon: const Icon(Icons.star_rounded),
      ),
    );
  }
}

final class DirectMatterAddDeviceScreen extends StatefulWidget {
  const DirectMatterAddDeviceScreen({
    required this.controller,
    required this.deviceStore,
    super.key,
  });

  final DirectMatterController controller;
  final DirectDeviceStore deviceStore;

  @override
  State<DirectMatterAddDeviceScreen> createState() =>
      _DirectMatterAddDeviceScreenState();
}

final class _DirectMatterAddDeviceScreenState
    extends State<DirectMatterAddDeviceScreen> {
  final TextEditingController _name = TextEditingController(text: 'وسیلهٔ خانه');
  final TextEditingController _payload = TextEditingController();
  final TextEditingController _ssid = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _adding = false;
  String? _error;
  String _stage = 'کد روی وسیله را اسکن کن';
  int _step = 0;
  bool _showPassword = false;
  DirectMatterDevice? _pendingDevice;

  @override
  void dispose() {
    _name.dispose();
    _payload.dispose();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _DirectMatterQrScanner()),
    );
    if (payload != null && mounted) {
      setState(() {
        _payload.text = payload;
        _stage = 'کد دریافت شد';
      });
    }
  }

  Future<void> _commission() async {
    if (_adding) return;
    final name = _name.text.trim();
    final payload = _payload.text.trim();
    final ssid = _ssid.text.trim();
    if (name.isEmpty || !payload.startsWith('MT:') || ssid.isEmpty) {
      setState(() {
        _error = 'نام وسیله، کد اتصال و نام وای‌فای را بررسی کن.';
      });
      return;
    }

    setState(() {
      _adding = true;
      _error = null;
      _stage = _pendingDevice == null
          ? 'در حال اتصال وسیله… نزدیک آن بمان.'
          : 'در حال ذخیرهٔ وسیله…';
    });
    try {
      if (_pendingDevice == null) {
        final result = await widget.controller.commissionWifi(
          setupPayload: payload,
          ssid: ssid,
          password: _password.text,
        );
        _pendingDevice = DirectMatterDevice(
          nodeId: result.nodeId,
          name: name,
          onOffEndpoints: result.onOffEndpoints,
        );
      }
      final device = _pendingDevice!;
      await widget.deviceStore.save(device);
      if (mounted) {
        setState(() {
          _stage = 'وسیله اضافه شد';
          _adding = false;
          _pendingDevice = null;
        });
        Navigator.of(context).pop(device);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _stage = _pendingDevice == null
              ? 'اتصال کامل نشد'
              : 'وسیله متصل شد؛ ذخیره کامل نشد';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  void _next() {
    if (_step == 0 && !_payload.text.trim().startsWith('MT:')) {
      setState(
        () => _error = 'کد QR معتبر Matter را اسکن یا متن آن را وارد کن.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _step++;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const titles = <String>['کد اتصال', 'آماده‌کردن وسیله', 'وای‌فای خانه'];
    return PopScope(
      canPop: !_adding && _pendingDevice == null,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('افزودن وسیله'),
          leading: BackButton(
            onPressed: () {
              if (_adding || _pendingDevice != null) return;
              if (_step > 0) {
                setState(() {
                  _step--;
                  _error = null;
                });
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(
              'مرحلهٔ ${toPersianDigits(_step + 1)} از ۳',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              titles[_step],
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            if (_step == 0) ...<Widget>[
              const Icon(Icons.qr_code_2, size: 80),
              const SizedBox(height: 16),
              const Text(
                'کد QR روی وسیله یا جعبه را اسکن کن. برای این کار اجازهٔ دوربین لازم است.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('اسکن کد وسیله'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _payload,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'متن کد QR',
                  hintText: 'MT:…',
                  helperText: 'اگر متن QR را داری، اینجا وارد کن.',
                ),
              ),
            ],
            if (_step == 1) ...<Widget>[
              const Icon(Icons.bluetooth_searching, size: 64),
              const SizedBox(height: 16),
              const Text('وسیله روشن باشد و گوشی نزدیک آن بماند.'),
              const SizedBox(height: 16),
              const Text(
                'طبق راهنمای وسیله، آن را در حالت اتصال قرار بده. بازنشانی کارخانه با حالت اتصال فرق دارد.',
              ),
              const SizedBox(height: 16),
              const Text(
                'بلوتوث و وای‌فای را روشن کن. هنگام درخواست دسترسی به دستگاه‌های نزدیک، اجازه بده؛ در نسخه‌های قدیمی Android ممکن است اجازهٔ موقعیت لازم باشد.',
              ),
            ],
            if (_step == 2) ...<Widget>[
              const Text(
                'نام و رمز شبکه‌ای را وارد کن که وسیله باید به آن وصل شود.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ssid,
                enabled: !_adding && _pendingDevice == null,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'نام وای‌فای'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !_adding && _pendingDevice == null,
                textDirection: TextDirection.ltr,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'رمز وای‌فای',
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'پنهان‌کردن رمز' : 'نمایش رمز',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                enabled: !_adding && _pendingDevice == null,
                decoration: const InputDecoration(
                  labelText: 'نام وسیله',
                  helperText: 'مثلاً کلید پذیرایی',
                ),
              ),
              const SizedBox(height: 20),
              if (_adding) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_stage)),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 16),
              _MatterErrorNotice(error: _error!),
            ],
            const SizedBox(height: 24),
            if (_step < 2)
              OutlinedButton(
                onPressed: _next,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('ادامه'),
                ),
              )
            else
              FilledButton.icon(
                onPressed: _adding ? null : _commission,
                icon: const Icon(Icons.add_link),
                label: Text(
                  _adding
                      ? 'در حال اتصال…'
                      : _pendingDevice != null
                      ? 'ذخیرهٔ دوباره'
                      : 'اتصال وسیله',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _MatterErrorNotice extends StatelessWidget {
  const _MatterErrorNotice({required this.error});
  final String error;

  String get message {
    if (error.contains('matter_ble_failed'))
      return 'وسیله پیدا نشد. نزدیک آن بمان و حالت اتصال و بلوتوث را بررسی کن.';
    if (error.startsWith('Remove failed'))
      return 'حذف تأیید نشد. وسیله در فهرست باقی مانده؛ اتصال آن را بررسی کن و دوباره تلاش کن.';
    if (error.startsWith('Command failed'))
      return 'تغییر وضعیت تأیید نشد. وضعیت وسیله را دوباره بررسی کن.';
    if (error.startsWith('Sensor read failed')) return 'دادهٔ تازهٔ سنسور دریافت نشد. اتصال وسیله را بررسی کن و دوباره تلاش کن.';
    if (error.startsWith('Color command failed')) return 'رنگ تأیید نشد. برای دریافت رنگ واقعی، وضعیت را دوباره بررسی کن.';
    if (error.startsWith('Level command failed'))
      return 'تغییر شدت نور تأیید نشد. وضعیت وسیله را دوباره بررسی کن.';
    if (error.startsWith('Could not save discovered channels'))
      return 'کنترل‌های تازه پیدا شدند، اما ذخیره نشدند. دوباره وضعیت را بررسی کن.';
    if (error.startsWith('Could not refresh') || error.startsWith('Realtime'))
      return 'وضعیت تازه دریافت نشد. برق وسیله و اتصال به وای‌فای خانه را بررسی کن.';
    if (error.contains('initialization') || error.contains('not available'))
      return 'ارتباط مانیسا راه‌اندازی نشد. اپ را ببند و دوباره باز کن.';
    if (error.contains('PlatformException') ||
        error.contains('Exception') ||
        error.contains('Error'))
      return 'این مرحله کامل نشد. اتصال و دسترسی‌ها را بررسی کن و دوباره تلاش کن.';
    return error;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      if (message != error)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('جزئیات برای پشتیبانی'),
          children: <Widget>[
            SelectableText(
              // Native exception messages can contain setup data; expose only
              // the error code, never Wi-Fi credentials or onboarding payloads.
              RegExp(r'matter_[a-z_]+').firstMatch(error)?.group(0) ??
                  'connection_failed',
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
    ],
  );
}

final class _DirectMatterQrScanner extends StatefulWidget {
  const _DirectMatterQrScanner();

  @override
  State<_DirectMatterQrScanner> createState() => _DirectMatterQrScannerState();
}

final class _DirectMatterQrScannerState extends State<_DirectMatterQrScanner> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسکن کد وسیله')),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'کد QR روی وسیله را داخل کادر قرار بده.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || !raw.startsWith('MT:')) return;
    _handled = true;
    Navigator.of(context).pop(raw);
  }
}

final class _RoomNameDialog extends StatefulWidget {
  const _RoomNameDialog({
    required this.title,
    required this.actionLabel,
    required this.reservedNames,
    this.initialName = '',
  });

  final String title;
  final String actionLabel;
  final String initialName;
  final Set<String> reservedNames;

  @override
  State<_RoomNameDialog> createState() => _RoomNameDialogState();
}

final class _RoomNameDialogState extends State<_RoomNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'یک نام برای اتاق بنویس.');
      return;
    }
    final normalized = name.toLowerCase();
    if (widget.reservedNames
        .map((item) => item.trim().toLowerCase())
        .contains(normalized)) {
      setState(() => _error = 'اتاقی با این نام وجود دارد.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: 40,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: 'نام اتاق',
        helperText: 'مثلاً پذیرایی یا اتاق خواب',
        errorText: _error,
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('انصراف'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
    ],
  );
}

final class _HomeNameDialog extends StatefulWidget {
  const _HomeNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_HomeNameDialog> createState() => _HomeNameDialogState();
}

final class _HomeNameDialogState extends State<_HomeNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'یک نام برای خانه بنویس.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('نام خانه'),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: 40,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: 'نام خانه',
        helperText: 'مثلاً خانهٔ ما',
        errorText: _error,
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('انصراف'),
      ),
      FilledButton(onPressed: _submit, child: const Text('ذخیره')),
    ],
  );
}

final class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.initialName, required this.onSave,
    this.title = 'تغییر نام وسیله', this.emptyMessage = 'یک نام برای وسیله بنویس.'});
  final String title;
  final String emptyMessage;
  final String initialName;
  final Future<void> Function(String name) onSave;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

final class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = widget.emptyMessage);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(name);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'نام ذخیره نشد. دوباره تلاش کن.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: TextField(
          controller: _name,
          autofocus: true,
          enabled: !_saving,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: widget.title == 'تغییر نام خروجی' ? 'نام خروجی' : 'نام وسیله',
            helperText: widget.title == 'تغییر نام خروجی' ? 'مثلاً خروجی ۱ اتاق کودک' : 'مثلاً کلید پذیرایی',
            errorText: _error,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'در حال ذخیره…' : 'ذخیره'),
        ),
      ],
    ),
  );
}

final class _ChannelNamesDialog extends StatefulWidget {
  const _ChannelNamesDialog({
    required this.device,
    required this.onSave,
    required this.onTest,
    required this.canTest,
  });
  final DirectMatterDevice device;
  final Future<void> Function(Map<int, String> names) onSave;
  final Future<void> Function(int endpoint) onTest;
  final bool Function(int endpoint) canTest;

  @override
  State<_ChannelNamesDialog> createState() => _ChannelNamesDialogState();
}

final class _ChannelNamesDialogState extends State<_ChannelNamesDialog> {
  late final Map<int, TextEditingController> _names =
      <int, TextEditingController>{
        for (
          var index = 0;
          index < widget.device.onOffEndpoints.length;
          index++
        )
          widget.device.onOffEndpoints[index]: TextEditingController(
            text: widget.device.channelName(
              widget.device.onOffEndpoints[index],
              index,
            ),
          ),
      };
  bool _saving = false;
  int? _testing;
  String? _error;

  @override
  void dispose() {
    for (final controller in _names.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _testing != null) return;
    final names = <int, String>{};
    for (final entry in _names.entries) {
      final name = entry.value.text.trim();
      if (name.isEmpty) {
        setState(() => _error = 'برای همهٔ خروجی‌ها نام بنویس.');
        return;
      }
      names[entry.key] = name;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(names);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'نام خروجی‌ها ذخیره نشد. دوباره تلاش کن.';
        });
    }
  }

  Future<void> _test(int endpoint) async {
    if (_saving || _testing != null || !widget.canTest(endpoint)) return;
    setState(() {
      _testing = endpoint;
      _error = null;
    });
    await widget.onTest(endpoint);
    if (mounted) setState(() => _testing = null);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && _testing == null,
    child: AlertDialog(
      title: const Text('نام خروجی‌ها'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'هر نام به خروجی واقعی دستگاه متصل می‌ماند. برای شناسایی، خودت می‌توانی خروجی را امتحان کنی.',
            ),
            const SizedBox(height: 16),
            for (
              var index = 0;
              index < widget.device.onOffEndpoints.length;
              index++
            ) ...<Widget>[
              TextField(
                controller: _names[widget.device.onOffEndpoints[index]],
                enabled: !_saving && _testing == null,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: 'خروجی ${toPersianDigits(index + 1)}',
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed:
                      widget.canTest(widget.device.onOffEndpoints[index]) &&
                          !_saving &&
                          _testing == null
                      ? () => _test(widget.device.onOffEndpoints[index])
                      : null,
                  icon: _testing == widget.device.onOffEndpoints[index]
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new),
                  label: Text(
                    _testing == widget.device.onOffEndpoints[index]
                        ? 'در حال امتحان…'
                        : 'امتحان این خروجی',
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving || _testing != null
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _saving || _testing != null ? null : _save,
          child: Text(_saving ? 'در حال ذخیره…' : 'ذخیره'),
        ),
      ],
    ),
  );
}
