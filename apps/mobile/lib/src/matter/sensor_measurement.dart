import '../core/persian_digits.dart';

enum SensorMetric { temperature, humidity, occupancy, contactClosed }

bool isBinarySensor(SensorMetric metric) =>
    metric == SensorMetric.occupancy || metric == SensorMetric.contactClosed;

String sensorMetricLabel(SensorMetric metric) => switch (metric) {
  SensorMetric.temperature => 'دما',
  SensorMetric.humidity => 'رطوبت',
  SensorMetric.occupancy => 'تشخیص حضور',
  SensorMetric.contactClosed => 'در / پنجره',
};

SensorMetric sensorMetricFromWireName(String name) => switch (name) {
  'temperature' => SensorMetric.temperature,
  'humidity' => SensorMetric.humidity,
  'occupancy' => SensorMetric.occupancy,
  'contactClosed' => SensorMetric.contactClosed,
  _ => throw const FormatException('invalid sensor metric'),
};

/// Matter MeasuredValue: signed centi-degrees Celsius / unsigned centi-percent.
/// An absent key is unsupported. Environmental readings may be supported-null.
/// Non-nullable Matter booleans cross the channel as bool and normalize to 0/1
/// only inside this observation model; zero is never an unknown binary state.
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
      if (isBinarySensor(metric)) {
        if (value is! bool) throw const FormatException('invalid binary sensor state');
        values[metric] = value ? 1 : 0;
        continue;
      }
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
  if (isBinarySensor(metric)) {
    if (value != 0 && value != 1) throw const FormatException('invalid binary observation');
    return metric == SensorMetric.occupancy
        ? (value == 1 ? 'حضور تشخیص داده شد' : 'حضوری تشخیص داده نشده')
        : (value == 1 ? 'بسته' : 'باز');
  }
  // Preserve the protocol's two decimal places; trim trailing zeroes only.
  var number = (value / 100).toStringAsFixed(2);
  number = number.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  final localized = toPersianDigits(number).replaceAll('.', '٫');
  return metric == SensorMetric.temperature ? '$localized °C' : '$localized٪';
}
