import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/persian_digits.dart';
import '../design/manisa_theme.dart';
import 'direct_device_store.dart';
import 'level_control.dart';
import 'manual_scene.dart';
import 'scene_lighting_executor.dart';

final class ManualSceneScreen extends StatefulWidget {
  const ManualSceneScreen({required this.store, required this.devices,
    required this.execute, required this.runner, super.key});
  final SceneStore store;
  final List<DirectMatterDevice> Function() devices;
  final Future<bool> Function(SceneAction) execute;
  final SceneRunner runner;
  @override
  State<ManualSceneScreen> createState() => _ManualSceneScreenState();
}
final class _ManualSceneScreenState extends State<ManualSceneScreen> {
  List<ManualScene> _scenes = <ManualScene>[];
  final _results = <String,Map<String,SceneActionStatus>>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { widget.runner.cancel(); super.dispose(); }
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
    if (widget.runner.running) return;
    final only = retry ? _results[scene.id]?.entries.where((e)=>e.value!=SceneActionStatus.confirmed).map((e)=>e.key).toSet() : null;
    // run sets its guard synchronously, before the UI rebuild.
    final pending = widget.runner.run(scene,available:_available,execute:widget.execute,only:only);
    setState(() {});
    final result = await pending;
    if (mounted) setState(() => _results[scene.id] = <String,SceneActionStatus>{
      if (retry) ...?_results[scene.id], ...result});
  }
  @override
  Widget build(BuildContext context) {
    final busy = _saving || widget.runner.running;
    return PopScope(canPop:!widget.runner.running,child:Scaffold(
      appBar:AppBar(title:const Text('سناریوها')),
      floatingActionButton:FloatingActionButton.extended(
        onPressed:busy || _loading || _error!=null ? null : () => _edit(),
        icon:const Icon(Icons.add),label:const Text('سناریوی جدید')),
      body:_loading ? const Center(child:CircularProgressIndicator()) : ListView(
        padding:const EdgeInsets.fromLTRB(16,16,16,100),children:<Widget>[
          Text('یک لمس، چند تغییر', style:Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height:8),
          const Text('وضعیت خروجی‌ها، شدت نور و رنگ را ذخیره کن و نتیجهٔ واقعی هرکدام را ببین.'),
          const SizedBox(height:20),
          if (_error!=null) ...<Widget>[Text(_error!),TextButton(onPressed:_load,child:const Text('تلاش دوباره'))],
          if (_scenes.isEmpty && _error==null) const Card(child:Padding(
            padding:EdgeInsets.all(24),child:Column(children:<Widget>[
              Icon(Icons.auto_awesome_motion_outlined,size:40,color:ManisaColors.teal),
              SizedBox(height:12),
              Text('هنوز سناریویی نساخته‌ای.'),
              SizedBox(height:4),
              Text('برای نمونه، چراغ‌های موردنیاز مطالعه را در یک سناریو ذخیره کن.'),
            ]))),
          if (widget.runner.running) ...<Widget>[
            const DecoratedBox(decoration:BoxDecoration(color:ManisaColors.mint,
              borderRadius:BorderRadius.all(Radius.circular(16))),child:Padding(
              padding:EdgeInsets.all(14),child:Text('در حال اجرا؛ نتیجهٔ هر خروجی بررسی می‌شود…'))),
            TextButton(onPressed:() { widget.runner.cancel(); },child:const Text('توقف ادامهٔ اجرا')),
          ],
          for (final scene in _scenes) Padding(padding:const EdgeInsets.only(bottom:12),
            child:Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,children:<Widget>[
              Text(scene.name,style:Theme.of(context).textTheme.titleLarge),
              const SizedBox(height:10),
              for (final action in scene.actions) Padding(padding:const EdgeInsets.symmetric(vertical:4),
                child:Text('${_label(action)}: ${action.on ? 'روشن' : 'خاموش'}${action.level == null ? '' : ' · نور ${toPersianDigits(matterLevelToPercent(action.level!))}٪'}${action.hue == null ? '' : action.saturation == 0 ? ' · سفید' : ' · رنگ انتخاب‌شده'}'
                  '${_results[scene.id]?[action.key] == null ? '' : ' — ${_status(_results[scene.id]![action.key]!)}'}')),
              const SizedBox(height:12),
              Wrap(spacing:8,children:<Widget>[
                FilledButton(onPressed:busy?null:()=>_run(scene),child:const Text('اجرا')),
                if (_results[scene.id]?.values.any((s)=>s!=SceneActionStatus.confirmed)==true)
                  TextButton(onPressed:busy?null:()=>_run(scene,retry:true),child:const Text('تلاش مجدد موارد تأییدنشده')),
                TextButton(onPressed:busy?null:()=>_edit(scene),child:const Text('ویرایش')),
                TextButton(onPressed:busy?null:()=>_delete(scene),child:const Text('حذف')),
              ]),
              if (_results[scene.id]?.values.contains(SceneActionStatus.unknown)==true)
                const Text('برای نتیجهٔ نامشخص، ممکن است فرمان اجرا شده باشد. تلاش مجدد همان تنظیمات ذخیره‌شده را درخواست می‌کند.'),
            ])))),
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
  bool _configure = false;
  bool _allowExit = false;
  bool _confirmingExit = false;
  late final String _initialDraft;
  late final TextEditingController _name;
  late final Map<String,SceneAction> _actions;
  String? _error;
  @override
  void initState() { super.initState(); _name=TextEditingController(text:widget.scene?.name);
    _actions=<String,SceneAction>{for(final a in widget.scene?.actions??<SceneAction>[]) a.key:a};
    _configure = widget.scene != null;
    _initialDraft = _draft;
    _name.addListener(_nameChanged);
  }
  String get _draft => jsonEncode({'name': _name.text,
    'actions': _actions.values.map((a) => a.toJson()).toList()});
  bool get _dirty => _draft != _initialDraft;
  void _nameChanged() { if (mounted) setState(() {}); }

  Future<void> _exit() async {
    if (_saving || _confirmingExit) return;
    if (_dirty) {
      _confirmingExit = true;
      final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('تغییرات ذخیره نشده‌اند'),
        content: const Text('می‌خواهی بدون ذخیرهٔ این تغییرات خارج شوی؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ادامهٔ ویرایش')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('خروج بدون ذخیره')),
        ],
      ));
      _confirmingExit = false;
      if (!mounted || discard != true) return;
    }
    await _close();
  }
  Future<void> _close() async {
    setState(() => _allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }
  void _back() {
    if (_saving) return;
    if (_configure) {
      setState(() { _configure = false; _error = null; });
    } else { _exit(); }
  }
  Future<void> _saveScene() async {
    if (_saving) return;
    try {
      final scene = ManualScene(id: widget.scene?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text, actions: _actions.values.toList());
      setState(() { _saving = true; _error = null; });
      final saved = await widget.onSave(scene);
      if (!mounted) return;
      if (saved) { await _close(); } else {
        setState(() { _saving = false; _error = 'سناریو ذخیره نشد. دوباره تلاش کن.'; });
      }
    } on FormatException {
      if (mounted) setState(() => _error = 'نام و بین یک تا ۳۲ خروجی انتخاب کن.');
    }
  }
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
    final available = <String>{for (final d in widget.devices)
      for (final ep in d.onOffEndpoints) '${d.nodeId}:$ep'};
    final canProceed = _actions.isNotEmpty && _actions.length <= 32;
    return PopScope(
      canPop: _allowExit || (!_saving && !_configure && !_dirty),
      onPopInvokedWithResult: (didPop, result) { if (!didPop) _back(); },
      child: Scaffold(
        key: const ValueKey('scene-editor'),
        appBar: AppBar(
          leading: IconButton(key: const ValueKey('scene-editor-back'),
            tooltip: 'بازگشت', onPressed: _saving ? null : _back,
            icon: const Icon(Icons.arrow_back_rounded)),
          title: Text(widget.scene == null ? 'سناریوی جدید' : 'ویرایش سناریو'),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(_configure ? '۲ · تنظیم عملکرد' : '۱ · انتخاب خروجی‌ها',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_configure) ...[
            TextField(controller: _name, enabled: !_saving, maxLength: 60,
              decoration: const InputDecoration(labelText: 'نام سناریو')),
            const SizedBox(height: 8),
            const Text('این تنظیمات فقط هنگام اجرای سناریو اعمال می‌شوند.'),
          ] else ...[
            const Text('خروجی‌هایی را انتخاب کن که با این سناریو تغییر می‌کنند.'),
            if (available.isEmpty) const Padding(padding: EdgeInsets.only(top: 16),
              child: Text('هنوز خروجی قابل‌کنترلی اضافه نشده است.')),
          ],
          const SizedBox(height: 16),
          for (final device in widget.devices)
            for (final endpoint in device.onOffEndpoints)
              if (!_configure || _actions.containsKey('${device.nodeId}:$endpoint'))
                Padding(padding: const EdgeInsets.only(bottom: 12),
                  child: Card(child: Column(children: [
                    if (!_configure)
                      CheckboxListTile(
                        key: ValueKey('scene-select-${device.nodeId}:$endpoint'),
                        value: _actions.containsKey('${device.nodeId}:$endpoint'),
                        title: Text('${device.name} · ${device.channelName(endpoint, device.onOffEndpoints.indexOf(endpoint))}'),
                        onChanged: _saving || (!_actions.containsKey('${device.nodeId}:$endpoint') && _actions.length >= 32)
                          ? null : (checked) => setState(() {
                            final action = SceneAction(nodeId: device.nodeId, endpoint: endpoint, on: true);
                            if (checked == true) { _actions[action.key] = action; }
                            else { _actions.remove(action.key); }
                            _error = null;
                          }),
                      )
                    else ...[
                      ListTile(title: Text('${device.name} · ${device.channelName(endpoint, device.onOffEndpoints.indexOf(endpoint))}')),
                      SwitchListTile(
                        title: Text(_actions['${device.nodeId}:$endpoint']!.on ? 'روشن شود' : 'خاموش شود'),
                        value: _actions['${device.nodeId}:$endpoint']!.on,
                        onChanged: _saving ? null : (on) => setState(() =>
                          _actions['${device.nodeId}:$endpoint'] = SceneAction(nodeId: device.nodeId, endpoint: endpoint, on: on)),
                      ),
                      if (_actions['${device.nodeId}:$endpoint']!.on) _lighting(device, endpoint),
                    ],
                  ]))),
          for (final action in _actions.values.where((a) => !available.contains(a.key)).toList())
            ListTile(title: const Text('خروجی حذف‌شده یا در دسترس نیست'),
              trailing: IconButton(tooltip: 'حذف خروجی از سناریو', icon: const Icon(Icons.close),
                onPressed: _saving ? null : () => setState(() => _actions.remove(action.key)))),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(child: Padding(padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${toPersianDigits(_actions.length)} خروجی انتخاب شده'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_configure)
                  FilledButton(onPressed: _saving || !canProceed ? null : _saveScene,
                    child: Text(_saving ? 'در حال ذخیره…' : 'ذخیره'))
                else
                  FilledButton(key: const ValueKey('scene-next'),
                    onPressed: _saving || !canProceed ? null : () => setState(() { _configure = true; _error = null; }),
                    child: const Text('ادامه')),
                if (_configure) TextButton(onPressed: _saving ? null : _back, child: const Text('تغییر خروجی‌ها')),
                TextButton(onPressed: _saving ? null : _exit, child: const Text('انصراف')),
              ]),
            ]))),
        ),
      ),
    );
  }
}
