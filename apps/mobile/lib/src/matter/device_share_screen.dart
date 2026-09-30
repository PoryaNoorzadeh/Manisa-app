import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/persian_digits.dart';
import 'onboarding_services.dart';

class DeviceShareScreen extends StatefulWidget {
  const DeviceShareScreen({required this.nodeId, required this.name, super.key});
  final int nodeId;
  final String name;
  @override
  State<DeviceShareScreen> createState() => _DeviceShareScreenState();
}

class _DeviceShareScreenState extends State<DeviceShareScreen> with WidgetsBindingObserver {
  bool _busy = false;
  String? _qr;
  String? _error;
  DateTime? _expires;
  Timer? _timer;
  int get _seconds => _expires == null ? 0 : _expires!.difference(DateTime.now()).inSeconds.clamp(0, 180);
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) setState(() => _qr = null);
  }
  Future<void> _open() async {
    setState(() { _busy = true; _error = null; _qr = null; });
    try {
      final response = await onboardingChannel.invokeMapMethod<String, Object?>('openSharingWindow', {'nodeId': widget.nodeId});
      if (!mounted) return;
      if (response == null || !(response['qrCode'] as String).startsWith('MT:')) throw const FormatException();
      setState(() {
        _qr = response['qrCode'] as String;
        _expires = DateTime.fromMillisecondsSinceEpoch(response['expiresAt'] as int);
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        setState(() { if (_seconds == 0) { _qr = null; timer.cancel(); } });
      });
    } catch (error) { if (mounted) setState(() => _error = onboardingError(error)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('اشتراک‌گذاری وسیله')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Text(widget.name, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      const Text('فقط به فرد مورد اعتماد نشان بده؛ گوشی دوم دسترسی مستقل کنترل این وسیله را می‌گیرد.'),
      const SizedBox(height: 12),
      const Text('هر دو گوشی را به شبکهٔ خانه وصل کن. در گوشی دوم «افزودن وسیله» و سپس «وسیلهٔ اشتراکی» را انتخاب و این QR را اسکن کن.'),
      const SizedBox(height: 24),
      if (_qr != null && _seconds > 0) ...[
        Center(child: QrImageView(data: _qr!, size: 260, backgroundColor: Colors.white)),
        const SizedBox(height: 16),
        Center(child: Text('اعتبار کد: ${toPersianDigits(_seconds)} ثانیه')),
      ] else FilledButton.icon(onPressed: _busy || _seconds > 0 ? null : _open,
        icon: const Icon(Icons.qr_code_2), label: Text(_busy ? 'در حال آماده‌سازی…' : _seconds > 0 ? 'تا پایان اعتبار قبلی صبر کن' : 'ساخت کد موقت')),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!)),
      const SizedBox(height: 24),
      const Text('بستن صفحه دسترسی فرد اضافه‌شده را لغو نمی‌کند. کد حداکثر ۳ دقیقه معتبر است؛ مدیریت و حذف دسترسی از گوشی دوم انجام می‌شود.'),
    ]),
  );
}
