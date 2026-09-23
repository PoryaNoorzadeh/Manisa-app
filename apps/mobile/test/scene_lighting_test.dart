import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/color_control.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/manual_scene.dart';
import 'package:manisa_mobile/src/matter/scene_lighting_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/scene-lighting');
  const controller = PlatformDirectMatterController(methods:channel);
  const device = DirectMatterDevice(nodeId:7,name:'نور',onOffEndpoints:<int>[1],
    levelEndpoints:<int>[1],colorCapabilities:<int,int>{1:1});
  const action = SceneAction(nodeId:7,endpoint:1,on:true,level:127,hue:85,saturation:254);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(()=>messenger.setMockMethodCallHandler(channel,null));
  test('legacy action loads unchanged; lighting roundtrip and invalid combinations',() {
    final old=SceneAction.fromJson(<String,Object?>{'nodeId':7,'endpoint':1,'on':false});
    expect(old.level,isNull); expect(old.hue,isNull);
    final saved=SceneAction.fromJson(action.toJson());
    expect(saved.level,127); expect(saved.hue,85); expect(saved.saturation,254);
    for (final overrides in <Map<String,Object?>>[
      <String,Object?>{'level':0},<String,Object?>{'hue':255},
      <String,Object?>{'saturation':null},<String,Object?>{'on':false},
    ]) {
      expect(()=>SceneAction.fromJson(<String,Object?>{...action.toJson(),...overrides}),throwsFormatException);
    }
  });
  test('lighting commands use exact endpoint and require all readbacks',() async {
    final calls=<String>[]; bool mismatch=false;
    messenger.setMockMethodCallHandler(channel,(call) async {
      calls.add(call.method);
      final args=call.arguments as Map<Object?,Object?>;
      expect(args['nodeId'],7);
      if(call.method.startsWith('set')) expect(args['endpoint'],1);
      if(call.method=='setLevel') expect(args['level'],127);
      if(call.method=='setColor') {
        expect(args['mode'],'hs');expect(args['first'],85);expect(args['second'],254);
      }
      return switch(call.method) {
        'readOnOff'=>true,
        'readLevels'=><String,Object?>{'1':mismatch?126:127},
        'readColors'=><String,Object?>{'1':<String,int>{'capabilities':1,'mode':0,'hue':85,'saturation':254}},
        _=>null,
      };
    });
    Future<bool> run()=>executeSceneLighting(action:action,device:device,controller:controller,active:()=>true);
    expect(await run(),isTrue);
    expect(calls,<String>['setOnOff','setLevel','setColor','readOnOff','readLevels','readColors']);
    mismatch=true;expect(await run(),isFalse);
  });
  test('wrong or missing color is not confirmed; white ignores meaningless hue',() async {
    Map<String,int> observation=<String,int>{'capabilities':1,'mode':0,'hue':170,'saturation':254};
    messenger.setMockMethodCallHandler(channel,(call) async => switch(call.method) {
      'readOnOff'=>true,
      'readColors'=><String,Object?>{'1':observation},
      _=>null,
    });
    const colorOnly=SceneAction(nodeId:7,endpoint:1,on:true,hue:85,saturation:254);
    Future<bool> run(SceneAction a)=>executeSceneLighting(action:a,device:device,controller:controller,active:()=>true);
    expect(await run(colorOnly),isFalse);
    observation=<String,int>{'capabilities':1,'mode':0};
    expect(await run(colorOnly),isFalse);
    observation=<String,int>{'capabilities':1,'mode':0,'hue':170,'saturation':0};
    expect(await run(const SceneAction(nodeId:7,endpoint:1,on:true,hue:0,saturation:0)),isTrue);
  });
  test('XY-only color uses converted coordinates and verifies XY readback',() async {
    const xyDevice=DirectMatterDevice(nodeId:7,name:'نور',onOffEndpoints:<int>[1],colorCapabilities:<int,int>{1:8});
    const colorOnly=SceneAction(nodeId:7,endpoint:1,on:true,hue:85,saturation:254);
    final xy=hsvToXy(const HSVColor.fromAHSV(1,85*360/254,1,1));
    var mismatch=false;
    messenger.setMockMethodCallHandler(channel,(call) async {
      if(call.method=='setColor') {
        final args=call.arguments as Map<Object?,Object?>;
        expect(args['mode'],'xy');expect(args['first'],xy.x);expect(args['second'],xy.y);
      }
      return switch(call.method) {
        'readOnOff'=>true,
        'readColors'=><String,Object?>{'1':<String,int>{'capabilities':8,'mode':1,'x':xy.x+(mismatch?20:0),'y':xy.y}},
        _=>null,
      };
    });
    Future<bool> run()=>executeSceneLighting(action:colorOnly,device:xyDevice,controller:controller,active:()=>true);
    expect(await run(),isTrue);mismatch=true;expect(await run(),isFalse);
  });
  test('missing capability prevents even the first write',() async {
    var calls=0;
    messenger.setMockMethodCallHandler(channel,(_)async{calls++;return null;});
    await expectLater(executeSceneLighting(action:action,
      device:const DirectMatterDevice(nodeId:7,name:'کلید',onOffEndpoints:<int>[1]),
      controller:controller,active:()=>true),throwsStateError);
    expect(calls,0);
  });
  test('deadline stops subsequent commands even after late completion',() async {
    final wait=Completer<Object?>();final calls=<String>[];
    messenger.setMockMethodCallHandler(channel,(call){calls.add(call.method);return wait.future;});
    await expectLater(executeSceneLighting(action:action,device:device,controller:controller,
      active:()=>true,budget:const Duration(milliseconds:5)),throwsA(isA<TimeoutException>()));
    wait.complete(null);await Future<void>.delayed(const Duration(milliseconds:5));
    expect(calls,<String>['setOnOff']);
  });
  test('target removal after command stops remaining writes',() async {
    var active=true;final calls=<String>[];
    messenger.setMockMethodCallHandler(channel,(call) async {calls.add(call.method);active=false;return null;});
    await expectLater(executeSceneLighting(action:action,device:device,controller:controller,
      active:()=>active),throwsStateError);
    expect(calls,<String>['setOnOff']);
  });
}
