import 'package:flutter/material.dart';

import '../core/persian_digits.dart';
import '../design/manisa_theme.dart';
import 'direct_device_store.dart';

/// Home is a summary; commands and state remain owned by the existing screen.
final class DeviceSummaryCard extends StatelessWidget {
  const DeviceSummaryCard({required this.device, required this.states,
    required this.unavailable, required this.onOpen, required this.onRefresh,
    required this.availability, required this.menu, this.roomName,
    this.primaryControl, this.errorMessage, super.key});

  final DirectMatterDevice device;
  final Map<String, bool> states;
  final bool unavailable;
  final String? roomName;
  final String? errorMessage;
  final Widget availability;
  final Widget menu;
  final Widget? primaryControl;
  final VoidCallback onOpen;
  final VoidCallback onRefresh;

  String get _summary {
    final outputs = device.onOffEndpoints;
    if (outputs.isEmpty) return 'اندازه‌گیری‌ها و کنترل‌ها در صفحهٔ وسیله';
    final known = outputs.where((e) => states.containsKey('${device.nodeId}:$e')).length;
    final on = outputs.where((e) => states['${device.nodeId}:$e'] == true).length;
    if (known == 0) return 'وضعیت ${toPersianDigits(outputs.length)} خروجی دریافت نشده';
    final count = '${toPersianDigits(on)} از ${toPersianDigits(outputs.length)} خروجی روشن';
    final unknown = known == outputs.length ? '' : ' · ${toPersianDigits(outputs.length-known)} نامشخص';
    return '${unavailable ? 'آخرین وضعیت: ' : ''}$count$unknown';
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsetsDirectional.only(end: 12, top: 4),
            child: Icon(Icons.devices_other_rounded, color: ManisaColors.tealPressed)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.name, style: Theme.of(context).textTheme.titleMedium),
            Text(device.productLabel, style: Theme.of(context).textTheme.bodySmall),
            Text(device.onOffEndpoints.isEmpty
                ? (roomName ?? 'بدون اتاق')
                : '${toPersianDigits(device.onOffEndpoints.length)} خروجی${roomName == null ? '' : ' · $roomName'}',
              style: Theme.of(context).textTheme.bodySmall),
          ])),
          menu,
        ]),
        const SizedBox(height: 8),
        availability,
        const SizedBox(height: 8),
        Text(_summary),
        if (primaryControl != null) primaryControl!,
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(errorMessage!, style: const TextStyle(color: ManisaColors.warning)),
        ],
        Wrap(spacing: 8, children: [
          TextButton.icon(
            key: ValueKey('open-device-${device.nodeId}'),
            onPressed: onOpen,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('کنترل وسیله'),
          ),
          if (unavailable || errorMessage != null)
            TextButton(onPressed: onRefresh, child: const Text('تلاش دوباره')),
        ]),
      ]),
    ),
  );
}
