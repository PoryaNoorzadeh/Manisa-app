import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/color_control.dart';
import 'package:manisa_mobile/src/matter/color_control_widget.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/manual_scene.dart';
import 'package:manisa_mobile/src/matter/manual_scene_screen.dart';

const a = SceneAction(nodeId:7,endpoint:1,on:false);
const b = SceneAction(nodeId:8,endpoint:2,on:true);
ManualScene scene() => ManualScene(id:'night',name:'شب',actions:<SceneAction>[a,b]);
final class FailingSceneStore extends MemorySceneStore {
  bool fail = true;
  @override
  Future<void> save(List<ManualScene> value) async {
    if (fail) throw StateError('disk');
    await super.save(value);
  }
}
void main() {
  test('scene round trip preserves exact output and explicit false; rejects duplicates', () {
    final restored=ManualScene.fromJson(jsonDecode(jsonEncode(scene().toJson())) as Map<String,Object?>);
    expect(restored.actions.first.on,isFalse);
    expect(restored.actions.last.key,'8:2');
    expect(()=>ManualScene(id:'x',name:' ',actions:<SceneAction>[a]),throwsFormatException);
    expect(()=>ManualScene(id:'x',name:'x',actions:<SceneAction>[a,a]),throwsFormatException);
    expect(()=>SceneAction.fromJson(<String,Object?>{'nodeId':7,'endpoint':0,'on':false}),throwsFormatException);
  });
  test('partial run continues; retry only unconfirmed actions and rejects duplicate runs', () async {
    final runner=SceneRunner(); final first=Completer<bool>(); final sent=<String>[];
    final pending=runner.run(scene(),available:(_)=>true,execute:(action) {
      sent.add(action.key); return action==a?first.future:Future<bool>.value(false);
    });
    await expectLater(runner.run(scene(),available:(_)=>true,execute:(_)async=>true),throwsStateError);
    first.complete(true);
    final results=await pending;
    expect(results,<String,SceneActionStatus>{a.key:SceneActionStatus.confirmed,b.key:SceneActionStatus.failed});
    await runner.run(scene(),available:(_)=>true,execute:(action)async{sent.add(action.key);return true;},
      only:results.entries.where((e)=>e.value!=SceneActionStatus.confirmed).map((e)=>e.key).toSet());
    expect(sent,<String>['7:1','8:2','8:2']);
  });
  test('timeout is unknown, deleted target is never sent, and no background replay', () async {
    final runner=SceneRunner(); var calls=0;
    final result=await runner.run(scene(),available:(action)=>action==a,
      execute:(_) { calls++; return Completer<bool>().future; },timeout:const Duration(milliseconds:2));
    expect(result[a.key],SceneActionStatus.unknown);
    expect(result[b.key],SceneActionStatus.unavailable);
    expect(calls,1); expect(runner.running,isFalse);
  });
  test('cancel stops unsent actions after an in-flight action completes', () async {
    final runner=SceneRunner(); final wait=Completer<bool>(); final calls=<String>[];
    final pending=runner.run(scene(),available:(_)=>true,execute:(a){calls.add(a.key);return wait.future;});
    runner.cancel(); wait.complete(true);
    final result=await pending;
    expect(calls,<String>['7:1']); expect(result[b.key],SceneActionStatus.cancelled);
  });
  testWidgets('scene editor keeps draft on save failure, persists and never executes on reopen', (tester) async {
    final store=FailingSceneStore(); var calls=0;
    Widget app()=>MaterialApp(home:ManualSceneScreen(store:store,
      devices:()=>const <DirectMatterDevice>[DirectMatterDevice(nodeId:7,name:'اتاق',onOffEndpoints:<int>[1])],
      execute:(_)async{calls++;return true;},runner:SceneRunner()));
    await tester.pumpWidget(app()); await tester.pumpAndSettle();
    await tester.tap(find.text('سناریوی جدید')); await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile)); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-next'))); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'شب');
    await tester.tap(find.byType(SwitchListTile)); await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره')); await tester.pumpAndSettle();
    expect(find.text('سناریو ذخیره نشد. دوباره تلاش کن.'),findsOneWidget);
    expect(find.text('شب'),findsOneWidget); expect(store.scenes,isEmpty);
    store.fail=false;
    await tester.tap(find.text('ذخیره')); await tester.pumpAndSettle();
    expect(store.scenes.single.actions.single.on,isFalse); expect(calls,0);
    await tester.tap(find.text('اجرا')); await tester.pumpAndSettle();
    expect(calls,1); expect(find.textContaining('تأیید شد'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app()); await tester.pumpAndSettle();
    expect(find.text('شب'),findsOneWidget); expect(calls,1);
    await tester.tap(find.text('حذف')); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'حذف')); await tester.pumpAndSettle();
    expect(store.scenes,isEmpty);
  });
  testWidgets('lighting editor saves targets without sending and preserves them on edit', (tester) async {
    tester.view.physicalSize = const Size(900,1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store=MemorySceneStore();var calls=0;
    await tester.pumpWidget(MaterialApp(home:ManualSceneScreen(store:store,
      devices:()=>const <DirectMatterDevice>[DirectMatterDevice(nodeId:7,name:'نور',
        onOffEndpoints:<int>[1],levelEndpoints:<int>[1],colorCapabilities:<int,int>{1:1})],
      execute:(_)async{calls++;return true;},runner:SceneRunner())));
    await tester.pumpAndSettle();await tester.tap(find.text('سناریوی جدید'));await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-next')));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'مطالعه');
    await tester.tap(find.text('تنظیم شدت نور'));await tester.pumpAndSettle();
    await tester.tap(find.text('تنظیم رنگ'));await tester.pumpAndSettle();
    await tester.tap(find.text('سفید'));await tester.pumpAndSettle();
    await tester.tap(find.text('تغییر خروجی‌ها'));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-next')));await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scene-level-7:1')),findsOneWidget);
    expect(tester.widget<Slider>(find.byKey(const ValueKey('scene-hue-7:1'))).value,0);
    await tester.tap(find.text('ذخیره'));await tester.pumpAndSettle();
    expect(calls,0);expect(store.scenes.single.actions.single.level,127);
    expect(store.scenes.single.actions.single.saturation,0);
    await tester.tap(find.text('ویرایش'));await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scene-level-7:1')),findsOneWidget);
    expect(find.byKey(const ValueKey('scene-hue-7:1')),findsOneWidget);
    await tester.tap(find.text('روشن شود'));await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));await tester.pumpAndSettle();
    final off=store.scenes.single.actions.single;
    expect(off.on,isFalse);expect(off.level,isNull);expect(off.hue,isNull);expect(calls,0);
  });
  testWidgets('wizard separates selection and preserves targets when changing outputs', (tester) async {
    final store = MemorySceneStore();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: ManualSceneScreen(store: store,
      devices: () => const [DirectMatterDevice(nodeId: 7, name: 'خانه', onOffEndpoints: [1, 2])],
      execute: (_) async { calls++; return true; }, runner: SceneRunner())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سناریوی جدید'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('scene-next'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('scene-select-7:1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-next')));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'شب');
    await tester.tap(find.text('روشن شود'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تغییر خروجی‌ها'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-select-7:2')));
    await tester.pumpAndSettle();
    expect(find.text('۲ خروجی انتخاب شده'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scene-next')));
    await tester.pumpAndSettle();
    expect(find.text('شب'), findsOneWidget);
    expect(find.text('خاموش شود'), findsOneWidget);
    expect(find.text('روشن شود'), findsOneWidget);
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(store.scenes.single.actions.map((a) => a.on), [false, true]);
    expect(calls, 0);
  });

  testWidgets('wizard guards unsaved system back and allows continuing or discarding', (tester) async {
    final store = MemorySceneStore();
    await tester.pumpWidget(MaterialApp(home: ManualSceneScreen(store: store,
      devices: () => const [DirectMatterDevice(nodeId: 7, name: 'خانه', onOffEndpoints: [1])],
      execute: (_) async => true, runner: SceneRunner())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سناریوی جدید'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-select-7:1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-next')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'پیش‌نویس');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('تغییرات ذخیره نشده‌اند'), findsOneWidget);
    await tester.tap(find.text('ادامهٔ ویرایش'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-next')));
    await tester.pumpAndSettle();
    expect(find.text('پیش‌نویس'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خروج بدون ذخیره'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scene-editor')), findsNothing);
    expect(store.scenes, isEmpty);
  });

  testWidgets('wizard prevents selecting a 33rd output', (tester) async {
    final store = MemorySceneStore();
    store.scenes = [ManualScene(id: 'many', name: 'خانه',
      actions: List.generate(32, (i) => SceneAction(nodeId: 7, endpoint: i+1, on: true)))];
    await tester.pumpWidget(MaterialApp(home: ManualSceneScreen(store: store,
      devices: () => [DirectMatterDevice(nodeId: 7, name: 'کلید', onOffEndpoints: List.generate(33, (i) => i+1))],
      execute: (_) async => true, runner: SceneRunner())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ویرایش'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تغییر خروجی‌ها'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('scene-select-7:33')), 300);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('scene-select-7:33'))).onChanged, isNull);
    expect(find.text('۳۲ خروجی انتخاب شده'), findsOneWidget);
  });

  testWidgets('pending scene save blocks back and is safe after disposal', (tester) async {
    final pending = Completer<void>();
    final store = PendingSceneStore(pending);
    store.scenes = [scene()];
    await tester.pumpWidget(MaterialApp(home: ManualSceneScreen(store: store,
      devices: () => const [DirectMatterDevice(nodeId: 7, name: 'خانه', onOffEndpoints: [1]),
        DirectMatterDevice(nodeId: 8, name: 'اتاق', onOffEndpoints: [2])],
      execute: (_) async => true, runner: SceneRunner())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'نام تازه');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('در حال ذخیره…'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scene-editor')), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('تغییرات ذخیره نشده‌اند'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('wizard footer remains usable at 360dp with 200 percent text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = MemorySceneStore();
    await tester.pumpWidget(MaterialApp(builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl, child: child!), home: ManualSceneScreen(store: store,
        devices: () => const [DirectMatterDevice(nodeId: 7, name: 'کلید چراغ پذیرایی و آشپزخانه',
          onOffEndpoints: [1], levelEndpoints: [1])],
        execute: (_) async => true, runner: SceneRunner())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سناریوی جدید'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-select-7:1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-next')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'روشنایی پذیرایی');
    expect(find.text('۱ خروجی انتخاب شده'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(store.scenes.single.name, 'روشنایی پذیرایی');
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop control cancels unsent actions without pretending to recall a sent command', (tester) async {
    final store=MemorySceneStore(); store.scenes=<ManualScene>[scene()];
    final pending=Completer<bool>(); final sent=<String>[];
    await tester.pumpWidget(MaterialApp(home:ManualSceneScreen(store:store,
      devices:()=>const <DirectMatterDevice>[
        DirectMatterDevice(nodeId:7,name:'اول',onOffEndpoints:<int>[1]),
        DirectMatterDevice(nodeId:8,name:'دوم',onOffEndpoints:<int>[2])],
      execute:(action){sent.add(action.key);return pending.future;},runner:SceneRunner())));
    await tester.pumpAndSettle(); await tester.tap(find.text('اجرا')); await tester.pump();
    await tester.tap(find.text('توقف ادامهٔ اجرا')); await tester.pump();
    pending.complete(true); await tester.pumpAndSettle();
    expect(sent,<String>['7:1']); expect(find.textContaining('متوقف شد'),findsOneWidget);
  });
  testWidgets('spectrum has no saturation control and drag commits a saturated color once', (tester) async {
    final sent=<HSVColor>[];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ColorControl(
      state:DirectColorState.fromMap(<String,int>{'capabilities':1,'mode':0,'hue':85,'saturation':0}),
      enabled:true,stale:false,onChanged:sent.add,onRefresh:(){}))));
    expect(find.textContaining('غلظت'),findsNothing);
    expect(find.byKey(const ValueKey('color-saturation')),findsNothing);
    expect(sent,isEmpty);
    final slider=find.byKey(const ValueKey('color-hue'));
    await tester.drag(slider,const Offset(90,0)); await tester.pumpAndSettle();
    expect(sent,hasLength(1)); expect(sent.single.saturation,1);
    expect(sent.single.value,1);
  });
}

final class PendingSceneStore extends MemorySceneStore {
  PendingSceneStore(this.pending);
  final Completer<void> pending;
  @override
  Future<void> save(List<ManualScene> value) async {
    await pending.future;
    await super.save(value);
  }
}
