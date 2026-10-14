import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/power_source.dart';
import 'package:manisa_mobile/src/matter/power_source_widget.dart';

PowerSource source([Map<String, Object?> extra = const <String, Object?>{}]) =>
    PowerSource.fromMap(<Object?, Object?>{'features': 2, 'status': 1, ...extra});
class Reader implements PowerSourceController {
  Reader(this.read);
  final Future<Map<int, PowerSource>> Function(int) read;
  @override
  Future<Map<int, PowerSource>> readPowerSources(int nodeId) => read(nodeId);
}
Widget panel(PowerSourceController reader, {int node = 7}) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: PowerSourcePanel(nodeId: node, controller: reader))));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('battery percentage uses half-percent units and preserves null and absence', () {
    expect(source(<String,Object?>{'percent':0}).percentage,'۰٪');
    expect(source(<String,Object?>{'percent':199}).percentage,'۹۹٫۵٪');
    expect(source(<String,Object?>{'percent':200}).percentage,'۱۰۰٪');
    expect(source(<String,Object?>{'percent':null}).percentage,'نامشخص');
    expect(source().values.containsKey('percent'),isFalse);
    for (final value in <Object?>[-1,201,100.0,'100',true]) {
      expect(() => source(<String,Object?>{'percent':value}),throwsFormatException);
    }
  });
  test('source features and forward enum values do not invent state', () {
    expect(source().kind,'باتری');
    expect(source(<String,Object?>{'features':1}).kind,'تغذیهٔ سیمی');
    expect(source(<String,Object?>{'features':3}).kind,'برق و باتری');
    expect(source(<String,Object?>{'features':0}).kind,'منبع تغذیه');
    expect(source(<String,Object?>{'chargeLevel':255,'status':255}).chargeLevel,'نامشخص');
    expect(source(<String,Object?>{'status':255}).status,'نامشخص');
    expect(() => source(<String,Object?>{'replacementNeeded':0}),throwsFormatException);
    expect(() => PowerSource.fromMap(<Object?,Object?>{'percent':100}),throwsFormatException);
    expect(() => source(<String,Object?>{'features':null}),throwsFormatException);
  });
  test('method channel retains root and multiple power source endpoints', () async {
    const channel = MethodChannel('test/power');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel,(call) async {
      expect(call.method,'readPowerSources');
      expect(call.arguments,<String,Object?>{'nodeId':7});
      return <String,Object?>{
        '0': <String,Object?>{'features':2,'status':1,'percent':199},
        '4': <String,Object?>{'features':1,'status':2,'wiredPresent':false}};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel,null));
    final result = await const PlatformDirectMatterController(methods:channel).readPowerSources(7);
    expect(result.keys,<int>[0,4]);
    expect(result[0]!.percentage,'۹۹٫۵٪');
    expect(result[4]!.values['wiredPresent'],false);
  });
  testWidgets('initial read, failure keeps last values, retry and unsupported hide', (tester) async {
    final first = Completer<Map<int,PowerSource>>();
    var calls = 0;
    final reader = Reader((_) { calls++; return switch(calls) {
      1 => first.future, 2 => Future<Map<int,PowerSource>>.error(Exception('offline')),
      _ => Future<Map<int,PowerSource>>.value(<int,PowerSource>{})}; });
    await tester.pumpWidget(panel(reader));
    expect(find.text('در حال دریافت اطلاعات تغذیه…'),findsOneWidget);
    expect(find.textContaining('شارژ باتری:'),findsNothing);
    first.complete(<int,PowerSource>{0:source(<String,Object?>{'percent':0,'chargeLevel':2,'replacementNeeded':true})});
    await tester.pumpAndSettle();
    expect(find.text('شارژ باتری: ۰٪'),findsOneWidget);
    expect(find.text('سطح باتری: بحرانی'),findsOneWidget);
    expect(find.text('باتری نیاز به تعویض دارد'),findsOneWidget);
    await tester.tap(find.text('به‌روزرسانی تغذیه'));
    await tester.pumpAndSettle();
    expect(find.text('شارژ باتری: ۰٪'),findsOneWidget);
    expect(find.textContaining('اطلاعات تازهٔ تغذیه دریافت نشد'),findsOneWidget);
    await tester.tap(find.text('به‌روزرسانی تغذیه'));
    await tester.pumpAndSettle();
    expect(find.text('باتری و تغذیه'),findsNothing);
  });
  testWidgets('late response cannot overwrite a different node or disposed panel', (tester) async {
    final late = Completer<Map<int,PowerSource>>();
    final reader = Reader((node) async => node == 7 ? late.future : <int,PowerSource>{0:source(<String,Object?>{'percent':200})});
    await tester.pumpWidget(panel(reader));
    await tester.pumpWidget(panel(reader,node:8));
    await tester.pumpAndSettle();
    late.complete(<int,PowerSource>{0:source(<String,Object?>{'percent':0})});
    await tester.pumpAndSettle();
    expect(find.text('شارژ باتری: ۱۰۰٪'),findsOneWidget);
    expect(find.text('شارژ باتری: ۰٪'),findsNothing);
    final removed = Completer<Map<int,PowerSource>>();
    await tester.pumpWidget(panel(Reader((_) => removed.future)));
    await tester.pumpWidget(const SizedBox.shrink());
    removed.complete(<int,PowerSource>{0:source()});
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
  });
  testWidgets('unsupported percentage stays absent and large Persian text fits', (tester) async {
    final reader = Reader((_) async => <int,PowerSource>{0:source(<String,Object?>{'chargeLevel':1})});
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size:Size(320,640),textScaler:TextScaler.linear(2.4)),
      child: Scaffold(body:SingleChildScrollView(child:SizedBox(width:280,
        child:PowerSourcePanel(nodeId:7,controller:reader)))))));
    await tester.pumpAndSettle();
    expect(find.textContaining('شارژ باتری:'),findsNothing);
    expect(find.text('سطح باتری: کم'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
