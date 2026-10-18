import 'package:flutter/material.dart';

import '../core/persian_digits.dart';
import '../design/manisa_localization.dart';
import '../design/manisa_theme.dart';
import 'direct_device_store.dart';
import 'sensor_measurement.dart';

/// Presentation only. The existing screen still owns commands and observations.
final class DeviceSummaryCard extends StatelessWidget {
  const DeviceSummaryCard({
    required this.device,
    required this.states,
    required this.unavailable,
    required this.onOpen,
    required this.onRefresh,
    required this.availability,
    required this.menu,
    this.roomName,
    this.primaryControl,
    this.errorMessage,
    this.sensorObservations = const {},
    this.now,
    super.key,
  });
  final DirectMatterDevice device;
  final Map<String, bool> states;
  final bool unavailable;
  final String? roomName, errorMessage;
  final Widget availability, menu;
  final Widget? primaryControl;
  final Map<String, SensorObservation> sensorObservations;
  final DateTime? now;
  final VoidCallback onOpen, onRefresh;
  bool get _on =>
      !unavailable &&
      device.onOffEndpoints.any((e) => states['${device.nodeId}:$e'] == true);
  int get _known => device.onOffEndpoints
      .where((e) => states.containsKey('${device.nodeId}:$e'))
      .length;
  String get _summary {
    final outputs = device.onOffEndpoints;
    if (outputs.isEmpty) return 'اندازه‌گیری‌ها و کنترل‌ها در صفحهٔ وسیله';
    final on = outputs
        .where((e) => states['${device.nodeId}:$e'] == true)
        .length;
    if (_known == 0)
      return 'وضعیت ${toPersianDigits(outputs.length)} خروجی دریافت نشده';
    final count =
        '${toPersianDigits(on)} از ${toPersianDigits(outputs.length)} خروجی روشن';
    final unknown = _known == outputs.length
        ? ''
        : ' · ${toPersianDigits(outputs.length - _known)} نامشخص';
    return '${unavailable ? 'آخرین وضعیت: ' : ''}$count$unknown';
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _on ? Colors.white : ManisaColors.ink;
    final muted = _on ? const Color(0xFFBEC7DC) : ManisaColors.mutedInk;
    final sensorOnly =
        device.onOffEndpoints.isEmpty && device.sensorCapabilities.isNotEmpty;
    return Card(
      color: _on ? ManisaColors.ink : ManisaColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12, top: 4),
                  child: Icon(
                    sensorOnly
                        ? Icons.sensors_rounded
                        : device.onOffEndpoints.any(device.isSocket)
                        ? Icons.power_outlined
                        : Icons.touch_app_outlined,
                    color: _on ? const Color(0xFF75E0DB) : ManisaColors.teal,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: foreground),
                      ),
                      AppText(
                        device.productLabel,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                menu,
              ],
            ),
            if (unavailable || (_known == 0 && !sensorOnly)) ...[
              const SizedBox(height: 8),
              availability,
            ],
            if (device.onOffEndpoints.length != 1 ||
                unavailable ||
                _known == 0) ...[
              const SizedBox(height: 8),
              AppText(_summary, style: TextStyle(color: foreground)),
            ],
            if (device.sensorCapabilities.isNotEmpty) ...[
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in device.sensorCapabilities.entries)
                      for (final metric in entry.value)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth,
                          ),
                          child: Builder(
                            builder: (context) {
                              final observation =
                                  sensorObservations['${device.nodeId}:${entry.key}'];
                              final value = observation?.values[metric];
                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  color: ManisaColors.canvas,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AppText(
                                        sensorMetricLabel(metric),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      if (value == null)
                                        const AppText('دریافت نشده')
                                      else
                                        Text(
                                          ManisaCopy.of(context).text(
                                            ManisaCopy.of(context).number(
                                              formatSensorValue(metric, value),
                                            ),
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      if (observation?.isStale(
                                            metric,
                                            now ?? DateTime.now(),
                                          ) ==
                                          true)
                                        const Wrap(
                                          spacing: 4,
                                          children: [
                                            Icon(
                                              Icons.update,
                                              size: 16,
                                              color: ManisaColors.warning,
                                            ),
                                            AppText(
                                              'نیاز به به‌روزرسانی',
                                              style: TextStyle(
                                                color: ManisaColors.warning,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                  ],
                ),
              ),
            ],
            if (primaryControl != null) primaryControl!,
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              AppText(
                errorMessage!,
                style: const TextStyle(color: ManisaColors.warning),
              ),
            ],
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: ValueKey('open-device-${device.nodeId}'),
                  style: TextButton.styleFrom(
                    foregroundColor: _on
                        ? const Color(0xFF75E0DB)
                        : ManisaColors.tealPressed,
                  ),
                  onPressed: onOpen,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const AppText('کنترل وسیله'),
                ),
                if (unavailable || errorMessage != null)
                  TextButton(
                    onPressed: onRefresh,
                    child: const AppText('تلاش دوباره'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
