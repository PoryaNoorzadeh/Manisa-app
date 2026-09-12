import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
  final Set<int> _refreshingNodes = <int>{};
  final Set<int> _removingNodes = <int>{};
  static const _readTimeout = Duration(seconds: 15);
  bool _loading = true;
  bool _editingMetadata = false;
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
      setState(() => _devices = devices);
      _events = widget.controller.watchOnOff().listen(
        (event) {
          if (!_canUpdate(event.nodeId)) return;
          setState(() {
            _states[_stateKey(event.nodeId, event.endpoint)] = event.value;
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!mounted) return;
          setState(() => _error = 'Realtime Matter update failed: $error');
        },
      );
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

  bool _canUpdate(int nodeId) => mounted &&
      !_removingNodes.contains(nodeId) &&
      _devices.any((device) => device.nodeId == nodeId);

  Future<void> _refreshAllStates() async {
    for (final device in List<DirectMatterDevice>.of(_devices)) {
      if (!_canUpdate(device.nodeId) || !_refreshingNodes.add(device.nodeId)) {
        continue;
      }
      try {
        // Read known channels first: a subscription/discovery failure must not
        // hide a successfully retrieved switch state.
        for (final endpoint in device.onOffEndpoints) {
          final value = await widget.controller.readOnOff(
            nodeId: device.nodeId,
            endpoint: endpoint,
          ).timeout(_readTimeout);
          if (!_canUpdate(device.nodeId)) break;
          setState(() => _states[_stateKey(device.nodeId, endpoint)] = value);
        }
        if (!_canUpdate(device.nodeId)) continue;
        final discovered = await widget.controller
            .discoverOnOffEndpoints(device.nodeId).timeout(_readTimeout);
        if (!_canUpdate(device.nodeId)) continue;
        if (discovered.isNotEmpty &&
            !_sameEndpoints(discovered, device.onOffEndpoints)) {
          final index = _devices.indexWhere((item) => item.nodeId == device.nodeId);
          setState(() {
            final updated = List<DirectMatterDevice>.of(_devices);
            updated[index] = updated[index].copyWith(onOffEndpoints: discovered);
            _devices = updated;
          });
          try {
            await widget.deviceStore.save(_devices[index]);
          } catch (error) {
            if (_canUpdate(device.nodeId)) {
              setState(() => _error = 'Could not save discovered channels: $error');
            }
          }
          for (final endpoint in discovered.where((e) => !device.onOffEndpoints.contains(e))) {
            final value = await widget.controller.readOnOff(
              nodeId: device.nodeId, endpoint: endpoint,
            ).timeout(_readTimeout);
            if (!_canUpdate(device.nodeId)) break;
            setState(() => _states[_stateKey(device.nodeId, endpoint)] = value);
          }
        }
        if (_canUpdate(device.nodeId) &&
            (_error?.startsWith('Could not refresh ${device.name}:') ?? false)) {
          setState(() => _error = null);
        }
      } catch (error) {
        if (_canUpdate(device.nodeId)) {
          setState(() {
            for (final endpoint in device.onOffEndpoints) {
              _states.remove(_stateKey(device.nodeId, endpoint));
            }
            _error = 'Could not refresh ${device.name}: $error';
          });
        }
      } finally {
        _refreshingNodes.remove(device.nodeId);
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
      _error = null;
    });
    try {
      await widget.controller.setOnOff(
        nodeId: device.nodeId,
        endpoint: endpoint,
        value: value,
      ).timeout(_readTimeout);
      final confirmed = await widget.controller.readOnOff(
        nodeId: device.nodeId,
        endpoint: endpoint,
      ).timeout(_readTimeout);
      if (_canUpdate(device.nodeId)) {
        setState(() => _states[key] = confirmed);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _states.remove(key);
          _error = 'Command failed: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(key));
      }
    }
  }



  Future<void> _manageChannels(DirectMatterDevice device) async {
    if (_editingMetadata || _removingNodes.isNotEmpty || !_canUpdate(device.nodeId)) return;
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
              _states[_stateKey(device.nodeId, endpoint)] != null &&
              !_busy.contains(_stateKey(device.nodeId, endpoint)),
          onSave: (names) async {
            final index = _devices.indexWhere((item) => item.nodeId == device.nodeId);
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
    if (_editingMetadata || _removingNodes.isNotEmpty || !_canUpdate(device.nodeId)) return;
    setState(() => _editingMetadata = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RenameDeviceDialog(
          initialName: device.name,
          onSave: (name) async {
            final current = _devices.firstWhere((item) => item.nodeId == device.nodeId);
            await widget.deviceStore.save(current.copyWith(name: name));
            if (!mounted) return;
            setState(() {
              _devices = _devices.map((item) => item.nodeId == device.nodeId
                  ? item.copyWith(name: name) : item).toList(growable: false);
            });
          },
        ),
      );
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
        content: Text('«${device.name}» از مانیسا حذف شود؟ برای افزودن دوباره، وسیله باید آمادهٔ اتصال باشد.'),
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
    if (confirmed != true || !mounted || _removingNodes.contains(device.nodeId)) return;
    setState(() {
      _removingNodes.add(device.nodeId);
      _error = null;
      for (final endpoint in device.onOffEndpoints) {
        _busy.add(_stateKey(device.nodeId, endpoint));
      }
    });
    try {
      // Only forget the device after the native RemoveCurrentFabric callback.
      await widget.controller.removeDevice(device.nodeId).timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException('Removal not confirmed; device kept in the list'),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مانیسا'),
        actions: <Widget>[
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
                  Text(
                    'خانهٔ من',
                    style: Theme.of(context).textTheme.headlineMedium,
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
                          onPressed: () => setState(() => _error = null),
                          child: const Text('بستن'),
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
                          onRename: () => _renameDevice(device),
                          onManageChannels: () => _manageChannels(device),
                          onRefresh: _refreshAllStates,
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
    required this.states,
    required this.busy,
    required this.onChanged,
    required this.onRemove,
    required this.onRename,
    required this.onManageChannels,
    required this.onRefresh,
  });

  final DirectMatterDevice device;
  final Map<String, bool> states;
  final Set<String> busy;
  final void Function(int endpoint, bool value) onChanged;
  final VoidCallback onRemove;
  final VoidCallback onRename;
  final VoidCallback onManageChannels;
  final VoidCallback onRefresh;

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
                      Text(
                        '${device.onOffEndpoints.length} خروجی',
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'تنظیمات وسیله',
                  onSelected: (value) {
                    if (value == 'remove') onRemove();
                    if (value == 'rename') onRename();
                    if (value == 'channels') onManageChannels();
                  },
                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(value: 'rename', child: Text('تغییر نام وسیله')),
                    PopupMenuItem(value: 'channels', child: Text('نام خروجی‌ها')),
                    PopupMenuItem(value: 'remove', child: Text('حذف وسیله')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (device.onOffEndpoints.isEmpty)
              TextButton(onPressed: onRefresh, child: const Text('دریافت کنترل‌های وسیله')),
            for (var index = 0;
                index < device.onOffEndpoints.length;
                index++)
              Builder(
                builder: (context) {
                  final endpoint = device.onOffEndpoints[index];
                  final key = _key(endpoint);
                  final state = states[key];
                  final isBusy = busy.contains(key);
                  if (state == null) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        device.channelName(endpoint, index),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: const Text('وضعیت دریافت نشده'),
                      leading: const Icon(Icons.help_outline),
                      trailing: TextButton(
                        onPressed: isBusy ? null : onRefresh,
                        child: const Text('بررسی'),
                      ),
                    );
                  }
                  return SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        device.channelName(endpoint, index),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    subtitle: Text(isBusy ? 'در حال انجام…' : state ? 'روشن' : 'خاموش'),
                    value: state,
                    onChanged: isBusy ? null : (next) => onChanged(endpoint, next),
                    secondary: isBusy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(state ? Icons.lightbulb : Icons.lightbulb_outline),
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
  final TextEditingController _name = TextEditingController(text: 'کلید خانه');
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
      _stage = _pendingDevice == null ? 'در حال اتصال وسیله… نزدیک آن بمان.' : 'در حال ذخیرهٔ وسیله…';
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
        setState(() { _stage = 'وسیله اضافه شد'; _adding = false; _pendingDevice = null; });
        Navigator.of(context).pop(device);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _stage = _pendingDevice == null ? 'اتصال کامل نشد' : 'وسیله متصل شد؛ ذخیره کامل نشد';
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
      setState(() => _error = 'کد QR معتبر Matter را اسکن یا متن آن را وارد کن.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _step++; _error = null; });
  }

  @override
  Widget build(BuildContext context) {
    const titles = <String>['کد اتصال', 'آماده‌کردن وسیله', 'وای‌فای خانه'];
    return PopScope(
      canPop: !_adding && _pendingDevice == null,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('افزودن وسیله'),
          leading: BackButton(onPressed: () {
            if (_adding || _pendingDevice != null) return;
            if (_step > 0) {
              setState(() { _step--; _error = null; });
            } else {
              Navigator.of(context).pop();
            }
          }),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text('مرحلهٔ ${_step + 1} از ۳', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(titles[_step], style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 24),
            if (_step == 0) ...<Widget>[
              const Icon(Icons.qr_code_2, size: 80),
              const SizedBox(height: 16),
              const Text('کد QR روی وسیله یا جعبه را اسکن کن. برای این کار اجازهٔ دوربین لازم است.'),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('اسکن کد وسیله')),
              const SizedBox(height: 16),
              TextField(controller: _payload, textDirection: TextDirection.ltr,
                autocorrect: false, enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'متن کد QR', hintText: 'MT:…', helperText: 'اگر متن QR را داری، اینجا وارد کن.')),
            ],
            if (_step == 1) ...<Widget>[
              const Icon(Icons.bluetooth_searching, size: 64),
              const SizedBox(height: 16),
              const Text('وسیله روشن باشد و گوشی نزدیک آن بماند.'),
              const SizedBox(height: 16),
              const Text('طبق راهنمای وسیله، آن را در حالت اتصال قرار بده. بازنشانی کارخانه با حالت اتصال فرق دارد.'),
              const SizedBox(height: 16),
              const Text('بلوتوث و وای‌فای را روشن کن. هنگام درخواست دسترسی به دستگاه‌های نزدیک، اجازه بده؛ در نسخه‌های قدیمی Android ممکن است اجازهٔ موقعیت لازم باشد.'),
            ],
            if (_step == 2) ...<Widget>[
              const Text('نام و رمز شبکه‌ای را وارد کن که وسیله باید به آن وصل شود.'),
              const SizedBox(height: 20),
              TextField(controller: _ssid, enabled: !_adding && _pendingDevice == null,
                textDirection: TextDirection.ltr, autocorrect: false, enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'نام وای‌فای')),
              const SizedBox(height: 16),
              TextField(controller: _password, enabled: !_adding && _pendingDevice == null,
                textDirection: TextDirection.ltr, obscureText: !_showPassword,
                autocorrect: false, enableSuggestions: false,
                decoration: InputDecoration(labelText: 'رمز وای‌فای', suffixIcon: IconButton(
                  tooltip: _showPassword ? 'پنهان‌کردن رمز' : 'نمایش رمز',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility)))),
              const SizedBox(height: 20),
              TextField(controller: _name, enabled: !_adding && _pendingDevice == null,
                decoration: const InputDecoration(labelText: 'نام وسیله', helperText: 'مثلاً کلید پذیرایی')),
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
              OutlinedButton(onPressed: _next, child: const Padding(
                padding: EdgeInsets.all(14), child: Text('ادامه')))
            else
              FilledButton.icon(
                onPressed: _adding ? null : _commission,
                icon: const Icon(Icons.add_link),
                label: Text(_adding ? 'در حال اتصال…' : _pendingDevice != null ? 'ذخیرهٔ دوباره' : 'اتصال وسیله')),
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
    if (error.contains('matter_ble_failed')) return 'وسیله پیدا نشد. نزدیک آن بمان و حالت اتصال و بلوتوث را بررسی کن.';
    if (error.startsWith('Remove failed')) return 'حذف تأیید نشد. وسیله در فهرست باقی مانده؛ اتصال آن را بررسی کن و دوباره تلاش کن.';
    if (error.startsWith('Command failed')) return 'تغییر وضعیت تأیید نشد. وضعیت وسیله را دوباره بررسی کن.';
    if (error.startsWith('Could not save discovered channels')) return 'کنترل‌های تازه پیدا شدند، اما ذخیره نشدند. دوباره وضعیت را بررسی کن.';
    if (error.startsWith('Could not refresh') || error.startsWith('Realtime')) return 'وضعیت تازه دریافت نشد. برق وسیله و اتصال به وای‌فای خانه را بررسی کن.';
    if (error.contains('initialization') || error.contains('not available')) return 'ارتباط مانیسا راه‌اندازی نشد. اپ را ببند و دوباره باز کن.';
    if (error.contains('PlatformException') || error.contains('Exception') || error.contains('Error')) return 'این مرحله کامل نشد. اتصال و دسترسی‌ها را بررسی کن و دوباره تلاش کن.';
    return error;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (message != error)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('جزئیات برای پشتیبانی'),
          children: <Widget>[SelectableText(
            // Native exception messages can contain setup data; expose only
            // the error code, never Wi-Fi credentials or onboarding payloads.
            RegExp(r'matter_[a-z_]+').firstMatch(error)?.group(0) ?? 'connection_failed',
            textDirection: TextDirection.ltr,
          )],
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

final class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.initialName, required this.onSave});
  final String initialName;
  final Future<void> Function(String name) onSave;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

final class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
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
      setState(() => _error = 'یک نام برای وسیله بنویس.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(name);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'نام ذخیره نشد. دوباره تلاش کن.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('تغییر نام وسیله'),
      content: SingleChildScrollView(
        child: TextField(
          controller: _name,
          autofocus: true,
          enabled: !_saving,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: 'نام وسیله',
            helperText: 'مثلاً کلید پذیرایی',
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
  late final Map<int, TextEditingController> _names = <int, TextEditingController>{
    for (var index = 0; index < widget.device.onOffEndpoints.length; index++)
      widget.device.onOffEndpoints[index]: TextEditingController(
        text: widget.device.channelName(widget.device.onOffEndpoints[index], index),
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
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(names);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'نام خروجی‌ها ذخیره نشد. دوباره تلاش کن.';
      });
    }
  }

  Future<void> _test(int endpoint) async {
    if (_saving || _testing != null || !widget.canTest(endpoint)) return;
    setState(() { _testing = endpoint; _error = null; });
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
            const Text('هر نام به خروجی واقعی دستگاه متصل می‌ماند. برای شناسایی، خودت می‌توانی خروجی را امتحان کنی.'),
            const SizedBox(height: 16),
            for (var index = 0; index < widget.device.onOffEndpoints.length; index++) ...<Widget>[
              TextField(
                controller: _names[widget.device.onOffEndpoints[index]],
                enabled: !_saving && _testing == null,
                maxLength: 40,
                decoration: InputDecoration(labelText: 'خروجی ${index + 1}'),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: widget.canTest(widget.device.onOffEndpoints[index]) &&
                          !_saving && _testing == null
                      ? () => _test(widget.device.onOffEndpoints[index])
                      : null,
                  icon: _testing == widget.device.onOffEndpoints[index]
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new),
                  label: Text(_testing == widget.device.onOffEndpoints[index]
                      ? 'در حال امتحان…'
                      : 'امتحان این خروجی'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving || _testing != null ? null : () => Navigator.of(context).pop(),
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
