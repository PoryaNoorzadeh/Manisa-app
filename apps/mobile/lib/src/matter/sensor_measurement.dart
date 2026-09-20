import '../core/persian_digits.dart';

enum SensorMetric { temperature, humidity }

SensorMetric sensorMetricFromWireName(String name) => switch (name) {
  'temperature' => SensorMetric.temperature,
  'humidity' => SensorMetric.humidity,
  _ => throw const FormatException('invalid sensor metric'),
};

/// Matter MeasuredValue: signed centi-degrees Celsius / unsigned centi-percent.
/// A present null means supported but unknown. An absent key is unsupported.
final class DirectSensorMeasurement {
  DirectSensorMeasurement(Map<SensorMetric, int?> values)
      : values = Map<SensorMetric, int?>.unmodifiable(values);
  final Map<SensorMetric, int?> values;
  Set<SensorMetric> get supported => values.keys.toSet();

  factory DirectSensorMeasurement.fromMap(Map<Object?, Object?> raw) {
    final values = <SensorMetric, int?>{};
    for (final metric in SensorMetric.values) {
      if (!raw.containsKey(metric.name)) continue;
      final value = raw[metric.name];
      final minimum = metric == SensorMetric.temperature ? -27315 : 0;
      final maximum = metric == SensorMetric.temperature ? 32767 : 10000;
      if (value != null &&
          (value is! int || value < minimum || value > maximum)) {
        throw const FormatException('invalid sensor measurement');
      }
      values[metric] = value as int?;
    }
    if (values.isEmpty) throw const FormatException('empty sensor measurement');
    return DirectSensorMeasurement(values);
  }
}

final class DirectSensorEvent {
  const DirectSensorEvent({required this.nodeId, required this.endpoint,
    this.report, this.staleMetrics = const <SensorMetric>{}});
  final int nodeId;
  final int endpoint;
  final DirectSensorMeasurement? report;
  final Set<SensorMetric> staleMetrics;

  factory DirectSensorEvent.fromMap(Map<Object?, Object?> raw) {
    final node = raw['nodeId'];
    final endpoint = raw['endpoint'];
    final values = raw['values'];
    final stale = raw['staleMetrics'];
    if (node is! int || node <= 0 || endpoint is! int || endpoint <= 0 || endpoint > 65534 ||
        (values != null && values is! Map<Object?, Object?>) ||
        (stale != null && stale is! List<Object?>)) {
      throw const FormatException('invalid sensor event');
    }
    final metrics = <SensorMetric>{};
    for (final name in (stale as List<Object?>? ?? const <Object?>[])) {
      if (name is! String) throw const FormatException('invalid stale sensor metric');
      metrics.add(sensorMetricFromWireName(name));
    }
    final report = values is Map<Object?, Object?> && values.isNotEmpty
        ? DirectSensorMeasurement.fromMap(values) : null;
    if (report == null && metrics.isEmpty) throw const FormatException('empty sensor event');
    return DirectSensorEvent(nodeId: node, endpoint: endpoint,
      report: report, staleMetrics: Set<SensorMetric>.unmodifiable(metrics));
  }
}

/// Volatile observations only. Per-metric versions keep delayed reads from
/// replacing a newer live report or clearing a more recent stream error.
final class SensorObservation {
  static const freshnessLimit = Duration(seconds: 90);
  final values = <SensorMetric, int?>{};
  final _received = <SensorMetric, DateTime>{};
  final _versions = <SensorMetric, int>{};
  final _stale = <SensorMetric>{};

  Map<SensorMetric, int> readVersion() => Map<SensorMetric, int>.of(_versions);

  void report(DirectSensorMeasurement report, DateTime now) {
    for (final entry in report.values.entries) {
      values[entry.key] = entry.value;
      _received[entry.key] = now;
      _stale.remove(entry.key);
      _versions[entry.key] = (_versions[entry.key] ?? 0) + 1;
    }
  }

  void read(DirectSensorMeasurement reading, Map<SensorMetric, int> started,
      DateTime now) {
    for (final entry in reading.values.entries) {
      if (_versions[entry.key] != started[entry.key]) continue;
      values[entry.key] = entry.value;
      _received[entry.key] = now;
      _stale.remove(entry.key);
    }
  }

  void markStale(Iterable<SensorMetric> metrics) {
    for (final metric in metrics) {
      _stale.add(metric);
      _versions[metric] = (_versions[metric] ?? 0) + 1;
    }
  }

  bool isStale(SensorMetric metric, DateTime now) {
    final received = _received[metric];
    return _stale.contains(metric) || (received != null &&
        now.difference(received) >= freshnessLimit);
  }
}

String formatSensorValue(SensorMetric metric, int value) {
  // Preserve the protocol's two decimal places; trim trailing zeroes only.
  var number = (value / 100).toStringAsFixed(2);
  number = number.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  final localized = toPersianDigits(number).replaceAll('.', '٫');
  return metric == SensorMetric.temperature ? '$localized °C' : '$localized٪';
}
