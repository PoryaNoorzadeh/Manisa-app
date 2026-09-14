import '../core/persian_digits.dart';

enum ElectricalMetric {
  activePower,
  voltage,
  activeCurrent,
  cumulativeEnergyImported,
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
