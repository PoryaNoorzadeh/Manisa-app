import '../core/persian_digits.dart';
import 'level_control.dart';
import 'scene_lighting_executor.dart';
import 'package:flutter/material.dart';

import 'direct_device_store.dart';
import 'manual_scene.dart';

final class ManualSceneScreen extends StatefulWidget {
  const ManualSceneScreen({required this.store, required this.devices,
    required this.execute, super.key});
  final SceneStore store;
  final List<DirectMatterDevice> Function() devices;
  final Future<bool> Function(SceneAction) execute;
  @override
  State<ManualSceneScreen> createState() => _ManualSceneScreenState();
}
final class _ManualSceneScreenState extends State<ManualSceneScreen> {
  List<ManualScene> _scenes = <ManualScene>[];
  final _runner = SceneRunner();
  final _results = <String,Map<String,SceneActionStatus>>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _runner.cancel(); super.dispose(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final value = await widget.store.load();
      if (mounted) setState(() => _scenes = value);
    } catch (_) { if (mounted) setState(() => _error = 'سناریوها خوانده نشدند؛ دوباره تلاش کن.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  String _label(SceneAction action) {
    for (final device in widget.devices()) {
      if (device.nodeId == action.nodeId && device.onOffEndpoints.contains(action.endpoint)) {
        return '${device.name} · ${device.channelName(action.endpoint, device.onOffEndpoints.indexOf(action.endpoint))}';
      }
    }
    return 'خروجی حذف‌شده یا در دسترس نیست';
  }
  bool _available(SceneAction action) => widget.devices().any((d) =>
      sceneActionSupported(action,d));
  Future<bool> _save(List<ManualScene> next) async {
    setState(() => _saving = true);
    try {
      await widget.store.save(next);
      if (mounted) setState(() { _scenes = next; _results.clear(); });
      return true;
    } catch (_) {
      return false;
    } finally { if (mounted) setState(() => _saving = false); }
  }
  Future<void> _edit([ManualScene? scene]) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => _SceneEditor(scene:scene,devices:widget.devices(),
        onSave:(result)=>_save(<ManualScene>[
          for (final old in _scenes) if (old.id != result.id) old, result]))));
  }
  Future<void> _delete(ManualScene scene) async {
    final yes = await showDialog<bool>(context:context,builder:(context) => AlertDialog(
      title:const Text('حذف سناریو؟'), content:Text(scene.name), actions:<Widget>[
        TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('انصراف')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('حذف'))]));
    if (yes == true && mounted) {
      final saved = await _save(_scenes.where((s)=>s.id!=scene.id).toList());
      if (!saved && mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('حذف سناریو ذخیره نشد. دوباره تلاش کن.')));
    }
  }
  Future<void> _run(ManualScene scene, {bool retry = false}) async {
    if (_runner.running) return;
    final only = retry ? _results[scene.id]?.entries.where((e)=>e.value!=SceneActionStatus.confirmed).map((e)=>e.key).toSet() : null;
    // run sets its guard synchronously, before the UI rebuild.
    final pending = _runner.run(scene,available:_available,execute:widget.execute,only:only);
    setState(() {});
    final result = await pending;
    if (mounted) setState(() => _results[scene.id] = <String,SceneActionStatus>{
      if (retry) ...?_results[scene.id], ...result});
  }
  @override
  Widget build(BuildContext context) {
    final busy = _saving || _runner.running;
    return PopScope(canPop:!_runner.running,child:Scaffold(
      appBar:AppBar(title:const Text('سناریوها')),
      floatingActionButton:FloatingActionButton.extended(
        onPressed:busy || _loading || _error!=null ? null : () => _edit(),
        icon:const Icon(Icons.add),label:const Text('سناریوی جدید')),
      body:_loading ? const Center(child:CircularProgressIndicator()) : ListView(
        padding:const EdgeInsets.fromLTRB(16,16,16,100),children:<Widget>[
          const Text('وضعیت خروجی‌ها، شدت نور و رنگ را با یک لمس تنظیم کن.'),
          if (_error!=null) ...<Widget>[Text(_error!),TextButton(onPressed:_load,child:const Text('تلاش دوباره'))],
          if (_scenes.isEmpty && _error==null) const Padding(padding:EdgeInsets.all(24),child:Text('هنوز سناریویی نساخته‌ای.')),
          if (_runner.running) ...<Widget>[
            const Padding(padding:EdgeInsets.all(12),child:Text('در حال اجرا؛ نتیجهٔ هر خروجی بررسی می‌شود…')),
            TextButton(onPressed:() { _runner.cancel(); },child:const Text('توقف ادامهٔ اجرا')),
          ],
          for (final scene in _scenes) Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,children:<Widget>[
              Text(scene.name,style:Theme.of(context).textTheme.titleLarge),
              for (final action in scene.actions) Padding(padding:const EdgeInsets.symmetric(vertical:4),
                child:Text('${_label(action)}: ${action.on ? 'روشن' : 'خاموش'}${action.level == null ? '' : ' · نور ${toPersianDigits(matterLevelToPercent(action.level!))}٪'}${action.hue == null ? '' : action.saturation == 0 ? ' · سفید' : ' · رنگ انتخاب‌شده'}'
                  '${_results[scene.id]?[action.key] == null ? '' : ' — ${_status(_results[scene.id]![action.key]!)}'}')),
              Wrap(spacing:8,children:<Widget>[
                FilledButton(onPressed:busy?null:()=>_run(scene),child:const Text('اجرا')),
                if (_results[scene.id]?.values.any((s)=>s!=SceneActionStatus.confirmed)==true)
                  TextButton(onPressed:busy?null:()=>_run(scene,retry:true),child:const Text('تلاش مجدد موارد تأییدنشده')),
                TextButton(onPressed:busy?null:()=>_edit(scene),child:const Text('ویرایش')),
                TextButton(onPressed:busy?null:()=>_delete(scene),child:const Text('حذف')),
              ]),
              if (_results[scene.id]?.values.contains(SceneActionStatus.unknown)==true)
                const Text('برای نتیجهٔ نامشخص، ممکن است فرمان اجرا شده باشد. تلاش مجدد همان تنظیمات ذخیره‌شده را درخواست می‌کند.'),
            ]))),
        ])));
  }
  String _status(SceneActionStatus status) => switch(status) {
    SceneActionStatus.confirmed => 'تأیید شد', SceneActionStatus.failed => 'تأیید نشد',
    SceneActionStatus.cancelled => 'متوقف شد',
    SceneActionStatus.unknown => 'نتیجه نامشخص', SceneActionStatus.unavailable => 'در دسترس نیست',
  };
}
final class _SceneEditor extends StatefulWidget {
  const _SceneEditor({required this.devices,required this.onSave,this.scene});
  final Future<bool> Function(ManualScene) onSave;
  final List<DirectMatterDevice> devices;
  final ManualScene? scene;
  @override
  State<_SceneEditor> createState()=>_SceneEditorState();
}
final class _SceneEditorState extends State<_SceneEditor> {
  bool _saving = false;
  late final TextEditingController _name;
  late final Map<String,SceneAction> _actions;
  String? _error;
  @override
  void initState() { super.initState(); _name=TextEditingController(text:widget.scene?.name);
    _actions=<String,SceneAction>{for(final a in widget.scene?.actions??<SceneAction>[]) a.key:a}; }
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  Widget _lighting(DirectMatterDevice device,int endpoint) {
    final key = '${device.nodeId}:$endpoint';
    final action = _actions[key]!;
    void change({int? level,int? hue,int? saturation}) => setState(() =>
      _actions[key] = SceneAction(nodeId:device.nodeId,endpoint:endpoint,on:true,
        level:level,hue:hue,saturation:saturation));
    final color = HSVColor.fromAHSV(1,(action.hue ?? 0)*360/254 % 360,
      (action.saturation ?? 254)/254,1).toColor();
    return Column(children:<Widget>[
      if (device.levelEndpoints.contains(endpoint)) ...<Widget>[
        SwitchListTile(title:const Text('تنظیم شدت نور'),
          subtitle:const Text('اگر خاموش باشد، شدت نور تغییر نمی‌کند.'),
          value:action.level != null,onChanged:_saving ? null : (enabled)=>change(
            level:enabled ? 127 : null,hue:action.hue,saturation:action.saturation)),
        if (action.level != null) Slider(key:ValueKey('scene-level-$key'),
          min:1,max:100,divisions:99,value:matterLevelToPercent(action.level!).toDouble(),
          label:'${toPersianDigits(matterLevelToPercent(action.level!))}٪',
          onChanged:_saving ? null : (v)=>change(level:percentToMatterLevel(v.round()),
            hue:action.hue,saturation:action.saturation)),
      ],
      if (((device.colorCapabilities[endpoint] ?? 0) & 9) != 0) ...<Widget>[
        SwitchListTile(title:const Text('تنظیم رنگ'),
          subtitle:const Text('رنگ دلخواه سناریو؛ فقط هنگام اجرا اعمال می‌شود.'),
          value:action.hue != null,onChanged:_saving ? null : (enabled)=>change(
            level:action.level,hue:enabled ? 0 : null,saturation:enabled ? 254 : null)),
        if (action.hue != null) ...<Widget>[
          Semantics(label:'رنگ انتخاب‌شده برای سناریو',child:CircleAvatar(backgroundColor:color)),
          Stack(alignment:Alignment.center,children:<Widget>[
            Container(height:18,margin:const EdgeInsets.symmetric(horizontal:24),
              decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),
                gradient:const LinearGradient(colors:<Color>[Colors.red,Colors.yellow,
                  Colors.green,Colors.cyan,Colors.blue,Colors.purple,Colors.red]))),
            Directionality(textDirection:TextDirection.ltr,child:SliderTheme(
              data:SliderTheme.of(context).copyWith(activeTrackColor:Colors.transparent,
                inactiveTrackColor:Colors.transparent,thumbColor:color),
              child:Slider(key:ValueKey('scene-hue-$key'),min:0,max:254,
                value:action.hue!.toDouble(),
                semanticFormatterCallback:(v)=>'رنگ ${toPersianDigits(v.round())}',
                onChanged:_saving ? null : (v)=>change(level:action.level,hue:v.round(),saturation:254)))),
          ]),
          ActionChip(label:const Text('سفید'),onPressed:_saving ? null : ()=>change(
            level:action.level,hue:0,saturation:0)),
        ],
      ],
      if ((action.level != null && !device.levelEndpoints.contains(endpoint)) ||
          (action.hue != null && ((device.colorCapabilities[endpoint] ?? 0) & 9) == 0))
        TextButton(onPressed:_saving ? null : ()=>change(),
          child:const Text('قابلیت نور تغییر کرده؛ حذف تنظیمات نور از این خروجی')),
    ]);
  }
  @override
  Widget build(BuildContext context) {
    final available=<String>{for(final d in widget.devices) for(final ep in d.onOffEndpoints) '${d.nodeId}:$ep'};
    return PopScope(canPop:!_saving,child:Scaffold(appBar:AppBar(title:Text(widget.scene==null?'سناریوی جدید':'ویرایش سناریو')),
      body:ListView(padding:const EdgeInsets.all(16),children:<Widget>[
        TextField(controller:_name,enabled:!_saving,maxLength:60,decoration:const InputDecoration(labelText:'نام سناریو')),
        const Text('خروجی‌ها را انتخاب کن و وضعیت دلخواه هرکدام را مشخص کن.'),
        for(final device in widget.devices) for(final endpoint in device.onOffEndpoints)
          Column(children:<Widget>[
            CheckboxListTile(value:_actions.containsKey('${device.nodeId}:$endpoint'),
              title:Text('${device.name} · ${device.channelName(endpoint,device.onOffEndpoints.indexOf(endpoint))}'),
              onChanged:_saving ? null : (checked)=>setState(() {
                final action=SceneAction(nodeId:device.nodeId,endpoint:endpoint,on:true);
                if(checked==true) { _actions[action.key]=action; } else { _actions.remove(action.key); }
              })),
            if(_actions.containsKey('${device.nodeId}:$endpoint')) SwitchListTile(
              title:Text(_actions['${device.nodeId}:$endpoint']!.on?'روشن شود':'خاموش شود'),
              value:_actions['${device.nodeId}:$endpoint']!.on,
              onChanged:_saving ? null : (on)=>setState(()=>_actions['${device.nodeId}:$endpoint']=SceneAction(nodeId:device.nodeId,endpoint:endpoint,on:on))),
            if (_actions['${device.nodeId}:$endpoint']?.on == true)
              _lighting(device,endpoint),
          ]),
        for(final action in _actions.values.where((a)=>!available.contains(a.key)).toList())
          ListTile(title:const Text('خروجی حذف‌شده یا در دسترس نیست'),
            trailing:IconButton(tooltip:'حذف خروجی از سناریو',icon:const Icon(Icons.close),
              onPressed:()=>setState(()=>_actions.remove(action.key)))),
        if(_error!=null) Text(_error!),
        FilledButton(onPressed:_saving ? null : () async {
          try {
            final scene=ManualScene(id:widget.scene?.id??DateTime.now().microsecondsSinceEpoch.toString(),
              name:_name.text,actions:_actions.values.toList());
            setState(()=>_saving=true);
            final saved = await widget.onSave(scene);
            if (!context.mounted) return;
            if (saved) { Navigator.pop(context); } else {
              setState(() { _saving=false; _error='سناریو ذخیره نشد. دوباره تلاش کن.'; });
            }
          } on FormatException { setState(()=>_error='نام و بین یک تا ۳۲ خروجی انتخاب کن.'); }
        },child:const Text('ذخیره')),
      ])));
  }
}
