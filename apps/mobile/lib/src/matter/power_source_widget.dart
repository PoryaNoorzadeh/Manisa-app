import 'dart:async';
import 'package:flutter/material.dart';
import '../core/persian_digits.dart';
import 'direct_matter_controller.dart';
import 'power_source.dart';

/// On-demand snapshots avoid periodic wakeups of battery devices. Refresh on
/// foreground resume, and label every value as a last read, never live telemetry.
final class PowerSourcePanel extends StatefulWidget {
  const PowerSourcePanel({required this.nodeId, required this.controller, super.key});
  final int nodeId;
  final PowerSourceController controller;
  @override
  State<PowerSourcePanel> createState() => _PowerSourcePanelState();
}
final class _PowerSourcePanelState extends State<PowerSourcePanel>
    with WidgetsBindingObserver {
  Map<int, PowerSource>? _sources;
  bool _busy = false;
  bool _error = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_read());
  }
  @override
  void didUpdateWidget(PowerSourcePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId || oldWidget.controller != widget.controller) {
      _generation++;
      _sources = null;
      _busy = false;
      _error = false;
      unawaited(_read());
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_read());
  }
  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> _read() async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() { _busy = true; _error = false; });
    try {
      final sources = await widget.controller.readPowerSources(widget.nodeId)
          .timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation) return;
      setState(() => _sources = sources);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = true);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_sources?.isEmpty == true && !_error) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const Text('باتری و تغذیه'),
        if (_sources == null && !_error) const Text('در حال دریافت اطلاعات تغذیه…'),
        for (final entry in (_sources ?? <int, PowerSource>{}).entries) ...<Widget>[
          Text('${entry.value.kind} — ${entry.value.status}'
            '${_sources!.length > 1 ? ' (منبع ${toPersianDigits(entry.key)})' : ''}'),
          if (entry.value.battery) ...<Widget>[
            if (entry.value.values.containsKey('percent')) Text('شارژ باتری: ${entry.value.percentage}'),
            if (entry.value.values.containsKey('chargeLevel')) Text('سطح باتری: ${entry.value.chargeLevel}'),
            if (entry.value.values.containsKey('chargeState')) Text(entry.value.chargeState),
            if (entry.value.values['replacementNeeded'] == true) const Text('باتری نیاز به تعویض دارد'),
          ],
          if (entry.value.wired && entry.value.values.containsKey('wiredPresent'))
            Text(entry.value.values['wiredPresent'] == true ? 'ورودی برق متصل است' : 'ورودی برق متصل نیست'),
        ],
        if (_sources?.isNotEmpty == true) const Text('مقادیر مربوط به آخرین دریافت هستند.'),
        if (_error) const Text('اطلاعات تازهٔ تغذیه دریافت نشد؛ دوباره تلاش کن.'),
        TextButton(onPressed: _busy ? null : _read,
          child: Text(_busy ? 'در حال دریافت…' : 'به‌روزرسانی تغذیه')),
      ]));
  }
}
