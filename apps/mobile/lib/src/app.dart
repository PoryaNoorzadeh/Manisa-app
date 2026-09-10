import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => MaterialApp(
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

final class DashboardScreen extends StatelessWidget {
  const DashboardScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.paired) {
            return _PairingScreen(controller: controller);
          }

          if (controller.loading && controller.homes.isEmpty) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                    'Make sure your phone is on the same local network as the hub, then enter the pairing code printed on the hub.',
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
                    icon: widget.controller.loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(widget.controller.loading ? 'Connecting…' : 'Pair Hub'),
                  ),
                  if (widget.controller.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      widget.controller.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    if (code.isEmpty) {
      return;
    }
    await widget.controller.pair(code);
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
          Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(controller.errorMessage!, textAlign: TextAlign.center),
          ),
        ],
      );
    }

    if (controller.homes.isEmpty) {
      return ListView(
        children: const <Widget>[
          SizedBox(height: 120),
          Icon(Icons.home_outlined, size: 52),
          SizedBox(height: 16),
          Center(child: Text('No Manisa home configured yet')),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          controller.homes.firstWhere((home) => home.id == controller.selectedHomeId).name,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
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
  Widget build(BuildContext context) => Column(
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
