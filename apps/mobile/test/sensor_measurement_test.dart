import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/sensor_measurement.dart';
import 'package:manisa_mobile/src/matter/sensor_measurement_widget.dart';

const temperature = SensorMetric.temperature;
const humidity = SensorMetric.humidity;
DirectSensorMeasurement reading(int? t, int? h) =>
    DirectSensorMeasurement.fromMap(<Object?, Object?>{'temperature': t, 'humidity': h});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('signed centi-degrees, centi-percent, zero and null remain distinct', () {
    expect(reading(-27315, 10000).values, <SensorMetric,int?>{temperature:-27315,humidity:10000});
    expect(reading(32767, 0).values[humidity], 0);
    expect(reading(0, null).values[temperature], 0);
    expect(reading(0, null).supported, <SensorMetric>{temperature,humidity});
    expect(DirectSensorMeasurement.fromMap(<Object?,Object?>{'humidity':null}).supported,
      <SensorMetric>{humidity});
    expect(formatSensorValue(temperature,-125), '-۱٫۲۵ °C');
    expect(formatSensorValue(temperature,0), '۰ °C');
    expect(formatSensorValue(humidity,10000), '۱۰۰٪');
    expect(formatSensorValue(humidity,1250), '۱۲٫۵٪');
  });

  test('rejects invalid wire measurements and malformed events', () {
    for (final raw in <Map<Object?,Object?>>[
      <Object?,Object?>{}, {'temperature':-32768}, {'temperature':32768},
      {'temperature':2.5}, {'humidity':-1}, {'humidity':10001}, {'humidity':'50'},
    ]) {
      expect(() => DirectSensorMeasurement.fromMap(raw), throwsFormatException);
    }
    for (final raw in <Map<Object?,Object?>>[
      {'nodeId':7,'endpoint':0,'values':{'temperature':0}},
      {'nodeId':7,'endpoint':65535,'values':{'temperature':0}},
      {'nodeId':7,'endpoint':1},
      {'nodeId':7,'endpoint':1,'staleMetrics':['unknown']},
      {'nodeId':7,'endpoint':1,'values':true},
    ]) { expect(() => DirectSensorEvent.fromMap(raw), throwsFormatException); }
    final event = DirectSensorEvent.fromMap(<Object?,Object?>{'nodeId':7,'endpoint':2,
      'values': <Object?,Object?>{'temperature':0}, 'staleMetrics':<Object?>['humidity']});
    expect(event.report!.values, <SensorMetric,int?>{temperature:0});
    expect(event.staleMetrics, <SensorMetric>{humidity});
  });

  test('sparse reports and freshness are independent per metric', () {
    final observation = SensorObservation();
    final now = DateTime.utc(2026,9,20);
    observation.read(reading(2100,4500), observation.readVersion(), now);
    expect(observation.isStale(temperature,now.add(const Duration(seconds:89))), isFalse);
    observation.markStale(<SensorMetric>{humidity});
    observation.report(DirectSensorMeasurement(<SensorMetric,int?>{temperature:0}),
      now.add(const Duration(seconds:60)));
    expect(observation.values, <SensorMetric,int?>{temperature:0,humidity:4500});
    expect(observation.isStale(humidity,now), isTrue);
    expect(observation.isStale(temperature,now.add(const Duration(seconds:90))), isFalse);
    expect(observation.isStale(temperature,now.add(const Duration(seconds:150))), isTrue);
    observation.report(DirectSensorMeasurement(<SensorMetric,int?>{humidity:null}), now);
    expect(observation.values[humidity], isNull);
    expect(observation.isStale(humidity,now), isFalse);
  });

  test('late reads cannot overwrite live reports or clear a newer error', () {
    final observation = SensorObservation();
    final now = DateTime.utc(2026,9,20);
    observation.report(reading(2000,4500),now);
    final started = observation.readVersion();
    observation.report(DirectSensorMeasurement(<SensorMetric,int?>{temperature:-500}),now);
    observation.markStale(<SensorMetric>{humidity});
    observation.read(reading(3000,5000),started,now);
    expect(observation.values, <SensorMetric,int?>{temperature:-500,humidity:4500});
    expect(observation.isStale(humidity,now),isTrue);
    observation.read(reading(2100,4200),observation.readVersion(),now);
    expect(observation.isStale(humidity,now),isFalse);
  });

  test('legacy metadata and sensor-only commissioning round trip without live values', () {
    final paired = DirectMatterCommissionResult.fromMap(<Object?,Object?>{
      'nodeId':7,'onOffEndpoints':<Object?>[]});
    final legacy = DirectMatterDevice.fromJson(<String,Object?>{
      'nodeId':paired.nodeId,'name':'اتاق کودک','onOffEndpoints':paired.onOffEndpoints});
    expect(legacy.sensorCapabilities,isEmpty);
    final updated = legacy.copyWith(sensorCapabilities:<int,Set<SensorMetric>>{
      2:<SensorMetric>{temperature,humidity}});
    final wire = jsonEncode(updated.toJson());
    final restored = DirectMatterDevice.fromJson(jsonDecode(wire) as Map<String,Object?>);
    expect(restored.productLabel,'سنسور محیطی');
    expect(restored.sensorCapabilities[2],<SensorMetric>{temperature,humidity});
    expect(wire, isNot(contains('received')));
    expect(wire, isNot(contains('values')));
  });

  const methods = MethodChannel('test/manisa/sensors');
  const events = EventChannel('test/manisa/sensor_events');
  const controller = PlatformDirectMatterController(methods:methods,sensorEvents:events);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(methods,null);
    messenger.setMockMethodCallHandler(const MethodChannel('test/manisa/sensor_events'),null);
  });

  test('native channel reads exact node and accepts a supported-null attribute', () async {
    messenger.setMockMethodCallHandler(methods,(call) async {
      expect(call.method,'readSensorMeasurements');
      expect(call.arguments,<String,Object?>{'nodeId':7});
      return <String,Object?>{'2':<String,Object?>{'temperature':-125,'humidity':null}};
    });
    final result = await controller.readSensorMeasurements(7);
    expect(result.keys,<int>[2]);
    expect(result[2]!.values,<SensorMetric,int?>{temperature:-125,humidity:null});
  });

  test('native channel rejects invalid endpoint, missing and out of range data', () async {
    for (final response in <Object?>[null, {'0':{'temperature':0}},
      {'65535':{'temperature':0}}, {'2':{'humidity':10001}}, {'2':false}]) {
      messenger.setMockMethodCallHandler(methods,(_) async => response);
      await expectLater(controller.readSensorMeasurements(7),throwsFormatException);
    }
    messenger.setMockMethodCallHandler(methods,(_) async => <String,Object?>{});
    expect(await controller.readSensorMeasurements(7),isEmpty);
  });

  test('native event channel preserves sparse values and nullable readings', () async {
    final listened = Completer<void>();
    messenger.setMockMethodCallHandler(const MethodChannel('test/manisa/sensor_events'),(call) async {
      if (call.method == 'listen') listened.complete();
      return null;
    });
    final next = controller.watchSensorMeasurements().first;
    await listened.future;
    await messenger.handlePlatformMessage(events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(<String,Object?>{
        'nodeId':7,'endpoint':2,'values':<String,Object?>{'humidity':null}}), (_) {});
    expect((await next).report!.values,<SensorMetric,int?>{humidity:null});
  });

  testWidgets('sensor-only device discovers real values even if OnOff discovery fails', (tester) async {
    final fake = _SensorController()..failDiscovery = true;
    final store = _SensorStore();
    await tester.pumpWidget(ManisaDirectApp(controller:fake,deviceStore:store));
    await tester.pumpAndSettle();
    expect(find.text('سنسور محیطی'), findsOneWidget);
    expect(find.text('۲۱٫۵ °C'), findsOneWidget);
    expect(find.text('۴۵٪'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('۰ خروجی'),findsNothing);
    expect(find.text('دریافت کنترل‌های وسیله'),findsNothing);
    expect(store.device.sensorCapabilities[2],<SensorMetric>{temperature,humidity});
    await tester.tap(find.byTooltip('تنظیمات وسیله'));
    await tester.pumpAndSettle();
    expect(find.text('نام خروجی‌ها'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await fake.close();
  });

  testWidgets('cached capability reopens unknown until fresh read; live reports are sparse', (tester) async {
    final fake = _SensorController();
    final store = _SensorStore();
    await tester.pumpWidget(ManisaDirectApp(controller:fake,deviceStore:store));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    fake.pending = Completer<Map<int,DirectSensorMeasurement>>();
    await tester.pumpWidget(ManisaDirectApp(controller:fake,deviceStore:store));
    await tester.pumpAndSettle();
    expect(find.text('۲۱٫۵ °C'),findsNothing);
    expect(find.text('دریافت نشده'),findsNWidgets(2));
    fake.pending!.complete(<int,DirectSensorMeasurement>{2:reading(0,null)});
    await tester.pumpAndSettle();
    expect(find.text('۰ °C'),findsOneWidget);
    expect(find.text('دریافت نشده'),findsOneWidget);
    fake.events.add(DirectSensorEvent(nodeId:7,endpoint:2,
      report:DirectSensorMeasurement(<SensorMetric,int?>{humidity:10000})));
    fake.events.add(DirectSensorEvent(nodeId:7,endpoint:9,report:reading(9000,100)));
    fake.events.add(DirectSensorEvent(nodeId:9,endpoint:2,report:reading(9000,100)));
    await tester.pumpAndSettle();
    expect(find.text('۰ °C'),findsOneWidget);
    expect(find.text('۱۰۰٪'),findsOneWidget);
    expect(find.text('۹۰ °C'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await fake.close();
  });

  testWidgets('failed read keeps last value stale and retry restores sensor-only node', (tester) async {
    final fake = _SensorController();
    await tester.pumpWidget(ManisaDirectApp(controller:fake,deviceStore:_SensorStore()));
    await tester.pumpAndSettle();
    fake.failRead = true;
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();
    expect(find.text('۲۱٫۵ °C'),findsOneWidget);
    expect(find.byIcon(Icons.update),findsNWidgets(2));
    fake.failRead = false;
    fake.value = reading(-150,0);
    await tester.ensureVisible(find.text('دریافت دوباره'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دریافت دوباره'));
    await tester.pumpAndSettle();
    expect(find.text('-۱٫۵ °C'),findsOneWidget);
    expect(find.text('۰٪'),findsOneWidget);
    expect(find.byIcon(Icons.update),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await fake.close();
  });

  testWidgets('late read cannot replace newer live sensor value or stream error', (tester) async {
    final fake = _SensorController();
    await tester.pumpWidget(ManisaDirectApp(controller:fake,deviceStore:_SensorStore()));
    await tester.pumpAndSettle();
    fake.pending = Completer<Map<int,DirectSensorMeasurement>>();
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();
    fake.events.add(DirectSensorEvent(nodeId:7,endpoint:2,
      report:DirectSensorMeasurement(<SensorMetric,int?>{temperature:-500}),
      staleMetrics:const <SensorMetric>{humidity}));
    await tester.pumpAndSettle();
    fake.pending!.complete(<int,DirectSensorMeasurement>{2:reading(3000,5000)});
    await tester.pumpAndSettle();
    expect(find.text('-۵ °C'),findsOneWidget);
    expect(find.text('۴۵٪'),findsOneWidget);
    expect(find.byIcon(Icons.update),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    fake.events.add(DirectSensorEvent(nodeId:7,endpoint:2,report:reading(0,0)));
    await tester.pump();
    expect(tester.takeException(),isNull);
    await fake.close();
  });

  testWidgets('optional sensor failure leaves switch usable', (tester) async {
    final fake = _SensorController()..endpoints = <int>[1];
    final store = _SensorStore()..device = const DirectMatterDevice(
      nodeId:7,name:'کلید و سنسور',onOffEndpoints:<int>[1]);
    await tester.binding.setSurfaceSize(const Size(600,1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ManisaDirectApp(controller:fake,deviceStore:store));
    await tester.pumpAndSettle();
    fake.failRead = true;
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.update),findsNWidgets(2));
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.onChanged,isNotNull);
    toggle.onChanged!(false);
    await tester.pumpAndSettle();
    expect(fake.commands,1);
    await tester.pumpWidget(const SizedBox.shrink());
    await fake.close();
  });

  testWidgets('removed sensor ignores pending reads and late reports', (tester) async {
    final fake = _SensorController();
    final store = _SensorStore();
    await tester.pumpWidget(ManisaDirectApp(controller:fake,deviceStore:store));
    await tester.pumpAndSettle();
    fake.pending = Completer<Map<int,DirectSensorMeasurement>>();
    await tester.tap(find.byTooltip('بررسی وضعیت'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تنظیمات وسیله'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف وسیله'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'حذف وسیله'));
    await tester.pumpAndSettle();
    expect(store.removed,isTrue);
    fake.pending!.complete(<int,DirectSensorMeasurement>{2:reading(3000,6000)});
    fake.events.add(DirectSensorEvent(nodeId:7,endpoint:2,report:reading(3000,6000)));
    await tester.pumpAndSettle();
    expect(find.byType(SensorMeasurementPanel),findsNothing);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await fake.close();
  });

  testWidgets('sensor values remain readable at large text scale on a narrow screen', (tester) async {
    final observation = SensorObservation()..report(reading(-123,10000),DateTime.utc(2026));
    await tester.binding.setSurfaceSize(const Size(320,1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:MediaQuery(
      data:const MediaQueryData(textScaler:TextScaler.linear(2)),
      child:Scaffold(body:Directionality(textDirection:TextDirection.rtl,
        child:SensorMeasurementPanel(supported:const <SensorMetric>{temperature,humidity},
          observation:observation,now:DateTime.utc(2027),onRefresh:() {}))))));
    await tester.pumpAndSettle();
    expect(find.text('-۱٫۲۳ °C'),findsOneWidget);
    expect(find.text('۱۰۰٪'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}

class _SensorStore implements DirectDeviceStore {
  DirectMatterDevice device = const DirectMatterDevice(nodeId:7,name:'اتاق کودک',onOffEndpoints:<int>[]);
  bool removed = false;
  @override
  Future<List<DirectMatterDevice>> load() async => removed ? <DirectMatterDevice>[] : <DirectMatterDevice>[device];
  @override
  Future<void> save(DirectMatterDevice value) async {
    device = DirectMatterDevice.fromJson(jsonDecode(jsonEncode(value.toJson())) as Map<String,Object?>);
  }
  @override
  Future<void> remove(int nodeId) async { removed = true; }
}

class _SensorController implements DirectMatterController, SensorMeasurementController {
  // Every test disposes its app before calling close().
  // ignore: close_sinks
  final events = StreamController<DirectSensorEvent>.broadcast();
  DirectSensorMeasurement value = reading(2150,4500);
  Completer<Map<int,DirectSensorMeasurement>>? pending;
  bool failRead = false;
  bool failDiscovery = false;
  bool switchOn = true;
  int commands = 0;
  List<int> endpoints = <int>[];
  Future<void> close() => events.close();
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<List<int>> discoverOnOffEndpoints(int nodeId) async {
    if (failDiscovery) throw StateError('OnOff unsupported');
    return endpoints;
  }
  @override
  Future<bool> readOnOff({required int nodeId,required int endpoint}) async => switchOn;
  @override
  Future<void> setOnOff({required int nodeId,required int endpoint,required bool value}) async {
    commands++; switchOn = value;
  }
  @override
  Stream<DirectMatterOnOffEvent> watchOnOff() => const Stream<DirectMatterOnOffEvent>.empty();
  @override
  Stream<DirectSensorEvent> watchSensorMeasurements() => events.stream;
  @override
  Future<Map<int,DirectSensorMeasurement>> readSensorMeasurements(int nodeId) async {
    if (failRead) throw StateError('sensor unavailable');
    if (pending != null) return pending!.future;
    return <int,DirectSensorMeasurement>{2:value};
  }
  @override
  Future<void> removeDevice(int nodeId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
