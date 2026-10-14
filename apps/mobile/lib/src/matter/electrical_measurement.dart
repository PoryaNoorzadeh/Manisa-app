import '../core/persian_digits.dart';

enum ElectricalMetric {
  activePower,
  voltage,
  activeCurrent,
  cumulativeEnergyImported,
}

ElectricalMetric electricalMetricFromWireName(String name) {
  for (final metric in ElectricalMetric.values) {
    if (metric.name == name) return metric;
  }
  throw const FormatException('invalid electrical metric');
}

final class DirectElectricalMeasurement {
  const DirectElectricalMeasurement({
    required this.supported,
    this.activePowerMilliwatts,
    this.voltageMillivolts,
    this.activeCurrentMilliamps,
    this.cumulativeEnergyImportedMilliwattHours,
  });

  final Set<ElectricalMetric> supported;
  final int? activePowerMilliwatts;
  final int? voltageMillivolts;
  final int? activeCurrentMilliamps;
  final int? cumulativeEnergyImportedMilliwattHours;

  DirectElectricalMeasurement merge(DirectElectricalMeasurement report) =>
      DirectElectricalMeasurement(
        supported: Set<ElectricalMetric>.unmodifiable(
          <ElectricalMetric>{...supported, ...report.supported},
        ),
        activePowerMilliwatts: report.supported.contains(ElectricalMetric.activePower)
            ? report.activePowerMilliwatts : activePowerMilliwatts,
        voltageMillivolts: report.supported.contains(ElectricalMetric.voltage)
            ? report.voltageMillivolts : voltageMillivolts,
        activeCurrentMilliamps: report.supported.contains(ElectricalMetric.activeCurrent)
            ? report.activeCurrentMilliamps : activeCurrentMilliamps,
        cumulativeEnergyImportedMilliwattHours: report.supported.contains(
          ElectricalMetric.cumulativeEnergyImported,
        ) ? report.cumulativeEnergyImportedMilliwattHours
          : cumulativeEnergyImportedMilliwattHours,
      );

  factory DirectElectricalMeasurement.fromMap(Map<Object?, Object?> value) {
    int? read(String key, {bool nonNegative = false}) {
      final raw = value[key];
      if (raw != null && (raw is! int || (nonNegative && raw < 0))) {
        throw const FormatException('invalid electrical measurement');
      }
      return raw as int?;
    }

    final supported = <ElectricalMetric>{};
    if (value.containsKey('activePowerMilliwatts')) {
      supported.add(ElectricalMetric.activePower);
    }
    if (value.containsKey('voltageMillivolts')) {
      supported.add(ElectricalMetric.voltage);
    }
    if (value.containsKey('activeCurrentMilliamps')) {
      supported.add(ElectricalMetric.activeCurrent);
    }
    if (value.containsKey('cumulativeEnergyImportedMilliwattHours')) {
      supported.add(ElectricalMetric.cumulativeEnergyImported);
    }
    if (supported.isEmpty) {
      throw const FormatException('electrical measurement has no supported fields');
    }
    return DirectElectricalMeasurement(
      supported: Set<ElectricalMetric>.unmodifiable(supported),
      activePowerMilliwatts: read('activePowerMilliwatts'),
      voltageMillivolts: read('voltageMillivolts'),
      activeCurrentMilliamps: read('activeCurrentMilliamps'),
      cumulativeEnergyImportedMilliwattHours: read(
        'cumulativeEnergyImportedMilliwattHours',
        nonNegative: true,
      ),
    );
  }
}

final class DirectElectricalEvent {
  const DirectElectricalEvent({required this.nodeId, required this.endpoint,
    required this.staleMetrics, this.report});

  final int nodeId;
  final int endpoint;
  final DirectElectricalMeasurement? report;
  final Set<ElectricalMetric> staleMetrics;

  factory DirectElectricalEvent.fromMap(Map<Object?, Object?> value) {
    final nodeId = value['nodeId'];
    final endpoint = value['endpoint'];
    final rawValues = value['values'];
    final rawStale = value['staleMetrics'];
    if (nodeId is! int || endpoint is! int || endpoint <= 0 ||
        (rawValues != null && rawValues is! Map<Object?, Object?>) ||
        (rawStale != null && rawStale is! List<Object?>)) {
      throw const FormatException('invalid electrical event');
    }
    DirectElectricalMeasurement? report;
    if (rawValues is Map<Object?, Object?> && rawValues.isNotEmpty) {
      report = DirectElectricalMeasurement.fromMap(rawValues);
    }
    final stale = <ElectricalMetric>{};
    for (final name in (rawStale as List<Object?>? ?? const <Object?>[])) {
      if (name is! String) throw const FormatException('invalid stale electrical metric');
      stale.add(electricalMetricFromWireName(name));
    }
    if (report == null && stale.isEmpty) {
      throw const FormatException('empty electrical event');
    }
    return DirectElectricalEvent(nodeId: nodeId, endpoint: endpoint,
      report: report, staleMetrics: Set<ElectricalMetric>.unmodifiable(stale));
  }
}

String formatElectricalValue(
  int value, {
  required int divisor,
  required int fractionDigits,
  required String unit,
}) {
  var number = (value / divisor).toStringAsFixed(fractionDigits);
  if (number.contains('.')) {
    number = number.replaceFirst(RegExp(r'0+$'), '');
    number = number.replaceFirst(RegExp(r'\.$'), '');
  }
  return '${toPersianDigits(number).replaceAll('.', '٫')} $unit';
}

String formatActivePower(int milliwatts) => formatElectricalValue(
  milliwatts,
  divisor: 1000,
  fractionDigits: 1,
  unit: 'وات',
);

String formatVoltage(int millivolts) => formatElectricalValue(
  millivolts,
  divisor: 1000,
  fractionDigits: 1,
  unit: 'ولت',
);

String formatActiveCurrent(int milliamps) => formatElectricalValue(
  milliamps,
  divisor: 1000,
  fractionDigits: 2,
  unit: 'آمپر',
);

String formatImportedEnergy(int milliwattHours) => formatElectricalValue(
  milliwattHours,
  divisor: 1000000,
  fractionDigits: 3,
  unit: 'کیلووات‌ساعت',
);
