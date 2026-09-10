import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'data/models.dart';
import 'state/app_controller.dart';

final class ManisaApp extends StatefulWidget {
  const ManisaApp({required this.controller, super.key});

  final AppController controller;

  @override
  State<ManisaApp> createState() => _ManisaAppState();
}

final class _ManisaAppState extends State<ManisaApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Manisa',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF324A3D),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: DashboardScreen(controller: widget.controller),
    );
  }
}

final class DashboardScreen extends StatelessWidget {
  const DashboardScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.paired) {
          return _PairingScreen(controller: controller);
        }
        if (controller.loading && controller.homes.isEmpty) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (controller.homes.isEmpty) {
          return _FirstHomeScreen(controller: controller);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Manisa'),
            actions: <Widget>[
              if (controller.homes.length > 1)
                PopupMenuButton<String>(
                  initialValue: controller.selectedHomeId,
                  onSelected: controller.selectHome,
                  itemBuilder: (context) => controller.homes
                      .map(
                        (home) => PopupMenuItem<String>(
                          value: home.id,
                          child: Text(home.name),
                        ),
                      )
                      .toList(growable: false),
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: controller.loading
                ? null
                : () => _openAddDevice(context, controller),
            icon: const Icon(Icons.add),
            label: const Text('Add Device'),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              final homeId = controller.selectedHomeId;
              if (homeId != null) {
                await controller.selectHome(homeId);
              }
            },
            child: _DashboardBody(controller: controller),
          ),
        );
      },
    );
  }

  Future<void> _openAddDevice(
    BuildContext context,
    AppController controller,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _AddDeviceScreen(controller: controller),
      ),
    );
  }
}

final class _PairingScreen extends StatefulWidget {
  const _PairingScreen({required this.controller});

  final AppController controller;

  @override
  State<_PairingScreen> createState() => _PairingScreenState();
}

final class _PairingScreenState extends State<_PairingScreen> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(Icons.home_work_outlined, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    'Connect to your Manisa Hub',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Make sure your phone and hub are on the same local network, then enter the pairing code printed on the hub.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _codeController,
                    enabled: !widget.controller.loading,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _pair(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Hub pairing code',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: widget.controller.loading ? null : _pair,
                    icon: const Icon(Icons.link),
                    label: Text(
                      widget.controller.loading ? 'Connecting…' : 'Pair Hub',
                    ),
                  ),
                  if (widget.controller.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      widget.controller.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim();
    if (code.isNotEmpty) {
      await widget.controller.pair(code);
    }
  }
}

final class _FirstHomeScreen extends StatefulWidget {
  const _FirstHomeScreen({required this.controller});

  final AppController controller;

  @override
  State<_FirstHomeScreen> createState() => _FirstHomeScreenState();
}

final class _FirstHomeScreenState extends State<_FirstHomeScreen> {
  final TextEditingController _nameController =
      TextEditingController(text: 'My Home');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(Icons.home_outlined, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    'Create your first home',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Home name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: widget.controller.loading
                        ? null
                        : () async {
                            await widget.controller.createHome(
                              _nameController.text,
                            );
                          },
                    child: const Text('Create Home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _AddDeviceScreen extends StatefulWidget {
  const _AddDeviceScreen({required this.controller});

  final AppController controller;

  @override
  State<_AddDeviceScreen> createState() => _AddDeviceScreenState();
}

final class _AddDeviceScreenState extends State<_AddDeviceScreen> {
  final TextEditingController _nameController =
      TextEditingController(text: 'Touch Switch');
  final TextEditingController _setupPayloadController = TextEditingController();
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _productType = 'switch_1gang';
  String _transport = 'matter_wifi';
  String? _roomId;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _setupPayloadController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Matter Device')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Device name',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _productType,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Product type',
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(
                value: 'switch_1gang',
                child: Text('Touch switch — 1 gang'),
              ),
              DropdownMenuItem(
                value: 'switch_2gang',
                child: Text('Touch switch — 2 gang'),
              ),
              DropdownMenuItem(
                value: 'switch_3gang',
                child: Text('Touch switch — 3 gang'),
              ),
              DropdownMenuItem(
                value: 'dimmer_1gang',
                child: Text('Touch dimmer — 1 gang'),
              ),
              DropdownMenuItem(value: 'socket', child: Text('Socket')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _productType = value);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _roomId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Room (optional)',
            ),
            items: widget.controller.rooms
                .map(
                  (room) => DropdownMenuItem<String>(
                    value: room.id,
                    child: Text(room.name),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _roomId = value),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment(value: 'matter_wifi', label: Text('Wi-Fi')),
              ButtonSegment(value: 'matter_thread', label: Text('Thread')),
            ],
            selected: <String>{_transport},
            onSelectionChanged: (selected) {
              setState(() => _transport = selected.first);
            },
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _setupPayloadController,
            readOnly: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Matter setup payload',
              hintText: 'MT:...',
              suffixIcon: IconButton(
                tooltip: 'Scan Matter QR',
                onPressed: _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Matter QR Code'),
          ),
          if (_transport == 'matter_wifi') ...<Widget>[
            const SizedBox(height: 20),
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Wi-Fi SSID',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Wi-Fi password',
              ),
            ),
          ],
          if (_transport == 'matter_thread') ...<Widget>[
            const SizedBox(height: 20),
            const Text(
              'Thread commissioning will use the Hub Thread dataset. OTBR integration is the next hardware step.',
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _commission,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_link),
            label: Text(_submitting ? 'Adding device…' : 'Add Device'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanQr() async {
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _MatterQrScanner()),
    );
    if (payload != null && mounted) {
      _setupPayloadController.text = payload;
    }
  }

  Future<void> _commission() async {
    final name = _nameController.text.trim();
    final setupPayload = _setupPayloadController.text.trim();
    if (name.isEmpty || !setupPayload.startsWith('MT:')) {
      setState(() => _error = 'Enter a name and scan a valid Matter QR code.');
      return;
    }
    if (_transport == 'matter_wifi' && _ssidController.text.trim().isEmpty) {
      setState(() => _error = 'Wi-Fi SSID is required.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.controller.commissionMatterDevice(
        name: name,
        productType: _productType,
        transport: _transport,
        setupPayload: setupPayload,
        roomId: _roomId,
        wifiSsid: _ssidController.text.trim(),
        wifiPassword: _passwordController.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

final class _MatterQrScanner extends StatefulWidget {
  const _MatterQrScanner();

  @override
  State<_MatterQrScanner> createState() => _MatterQrScannerState();
}

final class _MatterQrScannerState extends State<_MatterQrScanner> {
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
                  'Point the camera at the Matter QR code printed on the device.',
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
    if (_handled || capture.barcodes.isEmpty) {
      return;
    }
    final rawValue = capture.barcodes.first.rawValue;
    if (rawValue == null || !rawValue.startsWith('MT:')) {
      return;
    }
    _handled = true;
    Navigator.of(context).pop(rawValue);
  }
}

final class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.errorMessage != null && controller.devices.isEmpty) {
      return ListView(
        children: <Widget>[
          const SizedBox(height: 120),
          Icon(
            Icons.cloud_off,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              controller.errorMessage!,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          controller.homes
              .firstWhere((home) => home.id == controller.selectedHomeId)
              .name,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        if (controller.devices.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Column(
              children: <Widget>[
                Icon(Icons.devices_other_outlined, size: 52),
                SizedBox(height: 12),
                Text('No devices yet. Tap Add Device to commission one.'),
              ],
            ),
          ),
        for (final device in controller.devices)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DeviceCard(device: device, controller: controller),
          ),
      ],
    );
  }
}

final class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.controller});

  final Device device;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final descriptor = controller.descriptorFor(device.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(device.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(descriptor?.displayName ?? device.productType),
            const SizedBox(height: 16),
            if (descriptor == null)
              const LinearProgressIndicator()
            else
              for (final endpoint in descriptor.endpoints)
                _EndpointControls(
                  device: device,
                  endpoint: endpoint,
                  controller: controller,
                ),
          ],
        ),
      ),
    );
  }
}

final class _EndpointControls extends StatelessWidget {
  const _EndpointControls({
    required this.device,
    required this.endpoint,
    required this.controller,
  });

  final Device device;
  final EndpointDescriptor endpoint;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(endpoint.name, style: Theme.of(context).textTheme.titleMedium),
        for (final capability in endpoint.capabilities)
          _CapabilityControl(
            device: device,
            endpoint: endpoint.id,
            capability: capability,
            controller: controller,
          ),
        const Divider(height: 24),
      ],
    );
  }
}

final class _CapabilityControl extends StatelessWidget {
  const _CapabilityControl({
    required this.device,
    required this.endpoint,
    required this.capability,
    required this.controller,
  });

  final Device device;
  final int endpoint;
  final CapabilityDescriptor capability;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.stateFor(device.id, endpoint, capability.id);
    final value = state?.value;

    if (capability.id == 'on_off' && capability.writable) {
      final enabled = value == true;
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Power'),
        value: enabled,
        onChanged: (next) async {
          await controller.sendCommand(
            deviceId: device.id,
            endpoint: endpoint,
            capability: 'on_off',
            action: next ? 'on' : 'off',
          );
        },
      );
    }

    if (capability.id == 'level' && capability.writable) {
      final level = value is num ? value.toDouble().clamp(0, 100) : 0.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Brightness ${level.round()}%'),
          Slider(
            value: level,
            min: 0,
            max: 100,
            onChanged: (next) async {
              await controller.sendCommand(
                deviceId: device.id,
                endpoint: endpoint,
                capability: 'level',
                action: 'set_level',
                params: <String, Object?>{'level': next.round()},
              );
            },
          ),
        ],
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(capability.id.replaceAll('_', ' ')),
      trailing: Text(value?.toString() ?? '—'),
    );
  }
}
