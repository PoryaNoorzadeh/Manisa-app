import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'direct_device_store.dart';
import 'direct_matter_controller.dart';

final class ManisaDirectApp extends StatelessWidget {
  const ManisaDirectApp({
    required this.controller,
    required this.deviceStore,
    super.key,
  });

  final DirectMatterController controller;
  final DirectDeviceStore deviceStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Manisa',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF24A3A2),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: DirectMatterHomeScreen(
        controller: controller,
        deviceStore: deviceStore,
      ),
    );
  }
}

final class DirectMatterHomeScreen extends StatefulWidget {
  const DirectMatterHomeScreen({
    required this.controller,
    required this.deviceStore,
    super.key,
  });

  final DirectMatterController controller;
  final DirectDeviceStore deviceStore;

  @override
  State<DirectMatterHomeScreen> createState() => _DirectMatterHomeScreenState();
}

final class _DirectMatterHomeScreenState extends State<DirectMatterHomeScreen> {
  List<DirectMatterDevice> _devices = const <DirectMatterDevice>[];
  final Map<String, bool> _states = <String, bool>{};
  final Set<String> _busy = <String>{};
  StreamSubscription<DirectMatterOnOffEvent>? _events;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  String _stateKey(int nodeId, int endpoint) => '$nodeId:$endpoint';

  Future<void> _initialize() async {
    try {
      final supported = await widget.controller.isSupported();
      if (!supported) {
        throw StateError('Direct Matter is not available on this device.');
      }
      final devices = await widget.deviceStore.load();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
      _events = widget.controller.watchOnOff().listen(
        (event) {
          if (!mounted) return;
          setState(() {
            _states[_stateKey(event.nodeId, event.endpoint)] = event.value;
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!mounted) return;
          setState(() => _error = 'Realtime Matter update failed: $error');
        },
      );
      // A saved device may be offline, and the platform connection attempt can
      // consequently take a long time.  Do not keep onboarding behind that
      // refresh: render the saved devices first and update their state in the
      // background so Add Device remains available.
      unawaited(_refreshAllStates());
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshAllStates() async {
    for (final device in _devices) {
      try {
        final discovered = await widget.controller.discoverOnOffEndpoints(
          device.nodeId,
        );
        var currentDevice = device;
        if (discovered.isNotEmpty &&
            !_sameEndpoints(discovered, device.onOffEndpoints)) {
          currentDevice = device.copyWith(onOffEndpoints: discovered);
          await widget.deviceStore.save(currentDevice);
          final index = _devices.indexWhere((item) => item.nodeId == device.nodeId);
          if (index >= 0 && mounted) {
            setState(() {
              final updated = List<DirectMatterDevice>.of(_devices);
              updated[index] = currentDevice;
              _devices = updated;
            });
          }
        }
        for (final endpoint in currentDevice.onOffEndpoints) {
          final value = await widget.controller.readOnOff(
            nodeId: currentDevice.nodeId,
            endpoint: endpoint,
          );
          if (mounted) {
            setState(() {
              _states[_stateKey(currentDevice.nodeId, endpoint)] = value;
            });
          }
        }
      } catch (_) {
        // Keep the device visible while offline. A later refresh can reconnect.
      }
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
    });
    await _refreshAllStates();
  }

  Future<void> _setOnOff(
    DirectMatterDevice device,
    int endpoint,
    bool value,
  ) async {
    final key = _stateKey(device.nodeId, endpoint);
    if (_busy.contains(key)) return;
    setState(() {
      _busy.add(key);
      _error = null;
    });
    try {
      await widget.controller.setOnOff(
        nodeId: device.nodeId,
        endpoint: endpoint,
        value: value,
      );
      final confirmed = await widget.controller.readOnOff(
        nodeId: device.nodeId,
        endpoint: endpoint,
      );
      if (mounted) {
        setState(() => _states[key] = confirmed);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Command failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(key));
      }
    }
  }

  Future<void> _removeDevice(DirectMatterDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text('Remove ${device.name} from this Matter fabric?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.removeDevice(device.nodeId);
      await widget.deviceStore.remove(device.nodeId);
      if (mounted) {
        setState(() {
          _devices = _devices
              .where((item) => item.nodeId != device.nodeId)
              .toList(growable: false);
          for (final endpoint in device.onOffEndpoints) {
            _states.remove(_stateKey(device.nodeId, endpoint));
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Remove failed: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manisa'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refreshAllStates,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addDevice,
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAllStates,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: <Widget>[
                  Text(
                    'My Home',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Direct Matter · Local control',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 16),
                    MaterialBanner(
                      content: Text(_error!),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => setState(() => _error = null),
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_devices.isEmpty)
                    const _EmptyDirectMatterState()
                  else
                    for (final device in _devices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DirectMatterDeviceCard(
                          device: device,
                          states: _states,
                          busy: _busy,
                          onChanged: (endpoint, value) =>
                              _setOnOff(device, endpoint, value),
                          onRemove: () => _removeDevice(device),
                        ),
                      ),
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
              'Add your first device',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Scan the Matter QR code. Manisa will commission the device over BLE and then control it directly over Wi-Fi.',
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
    required this.states,
    required this.busy,
    required this.onChanged,
    required this.onRemove,
  });

  final DirectMatterDevice device;
  final Map<String, bool> states;
  final Set<String> busy;
  final void Function(int endpoint, bool value) onChanged;
  final VoidCallback onRemove;

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
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${device.onOffEndpoints.length} channel${device.onOffEndpoints.length == 1 ? '' : 's'}',
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'remove') onRemove();
                  },
                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0;
                index < device.onOffEndpoints.length;
                index++)
              Builder(
                builder: (context) {
                  final endpoint = device.onOffEndpoints[index];
                  final key = _key(endpoint);
                  final state = states[key];
                  final isBusy = busy.contains(key);
                  return SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Gang ${index + 1}'),
                    subtitle: Text('Matter endpoint $endpoint'),
                    value: state ?? false,
                    onChanged: state == null || isBusy
                        ? null
                        : (next) => onChanged(endpoint, next),
                    secondary: isBusy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(state == true
                            ? Icons.lightbulb
                            : Icons.lightbulb_outline),
                  );
                },
              ),
          ],
        ),
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
  final TextEditingController _name = TextEditingController(text: 'Touch Switch');
  final TextEditingController _payload = TextEditingController();
  final TextEditingController _ssid = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _adding = false;
  String? _error;
  String _stage = 'Ready to scan';

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
        _stage = 'QR code scanned';
      });
    }
  }

  Future<void> _commission() async {
    final name = _name.text.trim();
    final payload = _payload.text.trim();
    final ssid = _ssid.text.trim();
    if (name.isEmpty || !payload.startsWith('MT:') || ssid.isEmpty) {
      setState(() {
        _error = 'Enter a device name, scan a valid Matter QR, and enter Wi-Fi.';
      });
      return;
    }

    setState(() {
      _adding = true;
      _error = null;
      _stage = 'Commissioning over BLE…';
    });
    try {
      final result = await widget.controller.commissionWifi(
        setupPayload: payload,
        ssid: ssid,
        password: _password.text,
      );
      if (result.onOffEndpoints.isEmpty) {
        throw StateError('Device commissioned, but no OnOff endpoint was found.');
      }
      final device = DirectMatterDevice(
        nodeId: result.nodeId,
        name: name,
        onOffEndpoints: result.onOffEndpoints,
      );
      await widget.deviceStore.save(device);
      if (mounted) {
        setState(() => _stage = 'Device added');
        Navigator.of(context).pop(device);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _stage = 'Could not add device';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Device')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'Matter over Wi-Fi',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Manisa will use Bluetooth for initial commissioning, then control the device directly over your local Wi-Fi network.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            enabled: !_adding,
            decoration: const InputDecoration(
              labelText: 'Device name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _payload,
            enabled: !_adding,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Matter QR',
              hintText: 'MT:…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: _adding ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _adding ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Matter QR Code'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ssid,
            enabled: !_adding,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi name (SSID)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !_adding,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              if (_adding)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Expanded(child: Text(_stage)),
            ],
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _adding ? null : _commission,
            icon: const Icon(Icons.add_link),
            label: Text(_adding ? 'Adding…' : 'Add Device'),
          ),
        ],
      ),
    );
  }
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
      appBar: AppBar(title: const Text('Scan Matter QR')),
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
                  'Scan the Matter QR code printed on the switch.',
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
