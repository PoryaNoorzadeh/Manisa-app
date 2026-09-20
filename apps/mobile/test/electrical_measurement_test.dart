import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/electrical_measurement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodes supported fields while preserving zero and null', () {
    final measurement = DirectElectricalMeasurement.fromMap(
      <Object?, Object?>{
        'activePowerMilliwatts': 0,
        'voltageMillivolts': null,
        'cumulativeEnergyImportedMilliwattHours': 1250000,
      },
    );
    expect(
      measurement.supported,
      <ElectricalMetric>{
        ElectricalMetric.activePower,
        ElectricalMetric.voltage,
        ElectricalMetric.cumulativeEnergyImported,
      },
    );
    expect(measurement.activePowerMilliwatts, 0);
    expect(measurement.voltageMillivolts, isNull);
  });

  test('rejects missing fields, malformed values and negative imported energy', () {
    for (final raw in <Map<Object?, Object?>>[
      <Object?, Object?>{},
      <Object?, Object?>{'activePowerMilliwatts': '0'},
      <Object?, Object?>{'cumulativeEnergyImportedMilliwattHours': -1},
    ]) {
      expect(
        () => DirectElectricalMeasurement.fromMap(raw),
        throwsFormatException,
      );
    }
  });

  test('merges a partial report without losing other measurements', () {
    const previous = DirectElectricalMeasurement(
      supported: <ElectricalMetric>{ElectricalMetric.activePower, ElectricalMetric.voltage},
      activePowerMilliwatts: 12000, voltageMillivolts: 230000);
    final merged = previous.merge(DirectElectricalMeasurement.fromMap(
      <Object?, Object?>{'activePowerMilliwatts': 0}));
    expect(merged.activePowerMilliwatts, 0);
    expect(merged.voltageMillivolts, 230000);
  });

  test('decodes sparse live values and per-metric stale state', () {
    final value = DirectElectricalEvent.fromMap(<Object?, Object?>{
      'nodeId': 42, 'endpoint': 7,
      'values': <Object?, Object?>{'activePowerMilliwatts': 12500},
      'staleMetrics': <Object?>['voltage'],
    });
    expect(value.report!.activePowerMilliwatts, 12500);
    expect(value.staleMetrics, <ElectricalMetric>{ElectricalMetric.voltage});
    expect(() => DirectElectricalEvent.fromMap(<Object?, Object?>{
      'nodeId': 42, 'endpoint': 7,
    }), throwsFormatException);
  });

  test('formats Matter units with Persian digits and decimal separator', () {
    expect(formatActivePower(0), '۰ وات');
    expect(formatActivePower(12345), '۱۲٫۳ وات');
    expect(formatVoltage(230000), '۲۳۰ ولت');
    expect(formatActiveCurrent(125), '۰٫۱۳ آمپر');
    expect(formatImportedEnergy(1500000), '۱٫۵ کیلووات‌ساعت');
  });

  const channel = MethodChannel('test/manisa/electrical');
  const controller = PlatformDirectMatterController(methods: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reads measurements from the exact node contract', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readElectricalMeasurements');
      expect(call.arguments, <String, Object?>{'nodeId': 42});
      return <String, Object?>{
        '7': <String, Object?>{
          'activePowerMilliwatts': 12000,
          'voltageMillivolts': null,
        },
      };
    });

    final result = await controller.readElectricalMeasurements(42);
    expect(result.keys, <int>[7]);
    expect(result[7]!.activePowerMilliwatts, 12000);
    expect(result[7]!.supported, contains(ElectricalMetric.voltage));
  });

  test('rejects malformed native measurement response', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => <String, Object?>{'0': <String, Object?>{'activePowerMilliwatts': 1}},
    );
    await expectLater(
      controller.readElectricalMeasurements(42),
      throwsFormatException,
    );
  });
}
