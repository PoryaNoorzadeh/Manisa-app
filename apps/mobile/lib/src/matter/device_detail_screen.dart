import 'package:flutter/material.dart';

import 'direct_device_store.dart';

/// Resolves current metadata on every notification; never owns a controller.
final class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({required this.updates, required this.resolve,
    required this.controls, required this.onRefresh, super.key});

  final Listenable updates;
  final DirectMatterDevice? Function() resolve;
  final Widget Function(BuildContext, DirectMatterDevice) controls;
  final ValueChanged<DirectMatterDevice> onRefresh;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: updates,
    builder: (context, _) {
      final device = resolve();
      return Scaffold(
        key: const ValueKey('device-detail-screen'),
        appBar: AppBar(
          leading: const BackButton(key: ValueKey('device-detail-back')),
          title: const Text('کنترل وسیله'), actions: [
          if (device != null) IconButton(tooltip: 'بررسی وضعیت',
            onPressed: () => onRefresh(device), icon: const Icon(Icons.refresh)),
        ]),
        body: device == null
          ? Center(child: Padding(padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('این وسیله حذف شده است.'),
                TextButton(onPressed: () => Navigator.pop(context),
                  child: const Text('بازگشت به خانه')),
              ])))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: controls(context, device)),
      );
    },
  );
}
