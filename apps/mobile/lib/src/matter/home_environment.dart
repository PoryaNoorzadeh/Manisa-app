import 'package:flutter/material.dart';

import '../design/manisa_localization.dart';
import '../design/manisa_theme.dart';
import 'direct_device_store.dart';
import 'room_store.dart';
import 'sensor_measurement.dart';

/// Shows actual labeled source readings. Never invents an average or a value.
class HomeEnvironment extends StatelessWidget {
  const HomeEnvironment({
    required this.devices,
    required this.observations,
    required this.now,
    required this.roomName,
    required this.onOpen,
    required this.rooms,
    this.roomId,
    super.key,
  });
  final List<DirectMatterDevice> devices;
  final Map<String, SensorObservation> observations;
  final DateTime now;
  final String? Function(int) roomName;
  final ValueChanged<int> onOpen;
  final RoomCatalog rooms;
  final String? roomId;
  @override
  Widget build(BuildContext context) {
    final readings = <(DirectMatterDevice, SensorMetric, SensorObservation?)>[];
    for (final metric in [SensorMetric.temperature, SensorMetric.humidity]) {
      for (final device in devices) {
        if (roomId != null &&
            rooms.roomIdForDevice(device.nodeId) !=
                (roomId == 'unassigned' ? null : roomId))
          continue;
        final entries = device.sensorCapabilities.entries.where(
          (e) => e.value.contains(metric),
        );
        if (entries.isEmpty) continue;
        readings.add((
          device,
          metric,
          observations['${device.nodeId}:${entries.first.key}'],
        ));
        break;
      }
    }
    if (readings.isEmpty) return const SizedBox.shrink();
    final copy = ManisaCopy.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final single =
            MediaQuery.textScalerOf(context).scale(14) > 20 ||
            constraints.maxWidth < 300;
        final width = single
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final r in readings)
              SizedBox(
                width: width,
                child: Card(
                  child: InkWell(
                    onTap: () => onOpen(r.$1.nodeId),
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                r.$2 == SensorMetric.temperature
                                    ? Icons.thermostat_outlined
                                    : Icons.water_drop_outlined,
                                color: ManisaColors.teal,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppText(
                                  sensorMetricLabel(r.$2),
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            r.$3?.values[r.$2] == null
                                ? '—'
                                : copy.number(
                                    formatSensorValue(
                                      r.$2,
                                      r.$3!.values[r.$2]!,
                                    ),
                                  ),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            roomName(r.$1.nodeId) ?? r.$1.name,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (r.$3?.isStale(r.$2, now) == true)
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
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          if (r.$3?.values[r.$2] == null)
                            const AppText(
                              'دریافت نشده',
                              style: TextStyle(
                                color: ManisaColors.mutedInk,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
