import 'package:flutter/material.dart';

import 'sensor_measurement.dart';

final class SensorMeasurementPanel extends StatelessWidget {
  const SensorMeasurementPanel({required this.supported, required this.observation,
    required this.now, required this.onRefresh, this.title, super.key});
  final Set<SensorMetric> supported;
  final SensorObservation? observation;
  final DateTime now;
  final String? title;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      if (title != null) Text(title!, style: Theme.of(context).textTheme.titleSmall),
      for (final metric in SensorMetric.values)
        if (supported.contains(metric)) ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(metric == SensorMetric.temperature
              ? Icons.thermostat_outlined : Icons.water_drop_outlined),
          title: Text(metric == SensorMetric.temperature ? 'دما' : 'رطوبت'),
          subtitle: Text(observation?.values[metric] == null ? 'دریافت نشده'
              : formatSensorValue(metric, observation!.values[metric]!),
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.titleMedium),
          trailing: observation?.isStale(metric, now) == true
              ? const Tooltip(message: 'آخرین مقدار؛ نیاز به به‌روزرسانی',
                  child: Icon(Icons.update, semanticLabel: 'نیاز به به‌روزرسانی'))
              : null,
        ),
      if (supported.any((metric) => observation?.isStale(metric, now) == true))
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Text('نیاز به به‌روزرسانی'),
          TextButton(onPressed: onRefresh, child: const Text('دریافت دوباره')),
        ]),
    ]),
  );
}
