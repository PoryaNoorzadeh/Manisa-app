import 'package:flutter/material.dart';

import '../core/persian_digits.dart';
import 'manual_scene.dart';
import 'scene_automation.dart';

final class SceneAutomationScreen extends StatefulWidget {
  const SceneAutomationScreen({
    required this.store,
    required this.sceneStore,
    super.key,
  });

  final AutomationStore store;
  final SceneStore sceneStore;

  @override
  State<SceneAutomationScreen> createState() =>
      _SceneAutomationScreenState();
}

final class _SceneAutomationScreenState extends State<SceneAutomationScreen> {
  List<SceneAutomation> _automations = const <SceneAutomation>[];
  List<ManualScene> _scenes = const <ManualScene>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await Future.wait<Object>(<Future<Object>>[
        widget.store.load(),
        widget.sceneStore.load(),
      ]);
      if (!mounted) return;
      setState(() {
        _automations = loaded[0] as List<SceneAutomation>;
        _scenes = loaded[1] as List<ManualScene>;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'زمان‌بندی‌ها خوانده نشدند؛ دوباره تلاش کن.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _mutate(
    List<SceneAutomation> Function(List<SceneAutomation>) update,
  ) async {
    setState(() => _saving = true);
    try {
      final next = await widget.store.mutate(update);
      if (mounted) setState(() => _automations = next);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('زمان‌بندی ذخیره نشد. دوباره تلاش کن.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit([SceneAutomation? automation]) async {
    final result = await showDialog<SceneAutomation>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AutomationEditor(
        scenes: _scenes,
        automation: automation,
      ),
    );
    if (result == null || !mounted) return;
    await _mutate(
      (current) => <SceneAutomation>[
        for (final item in current)
          if (item.id != result.id) item,
        result,
      ],
    );
  }

  String _sceneName(SceneAutomation automation) => _scenes
      .where((scene) => scene.id == automation.sceneId)
      .map((scene) => scene.name)
      .firstOrNull ??
      'سناریوی حذف‌شده';

  String _days(Set<int> weekdays) {
    const labels = <int, String>{
      DateTime.saturday: 'ش',
      DateTime.sunday: 'ی',
      DateTime.monday: 'د',
      DateTime.tuesday: 'س',
      DateTime.wednesday: 'چ',
      DateTime.thursday: 'پ',
      DateTime.friday: 'ج',
    };
    return <int>[
      DateTime.saturday,
      DateTime.sunday,
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ].where(weekdays.contains).map((day) => labels[day]!).join('، ');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('زمان‌بندی‌ها')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _saving || _loading || _error != null || _scenes.isEmpty
          ? null
          : () => _edit(),
      icon: const Icon(Icons.add_alarm_outlined),
      label: const Text('زمان‌بندی جدید'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: <Widget>[
              const Text(
                'زمان‌بندی‌ها روی همین گوشی اجرا می‌شوند. اگر برنامه بسته باشد، '
                'اجرای عقب‌افتاده فقط تا ۱۰ دقیقه پس از بازگشت انجام می‌شود و '
                'هیچ فرمانی دوبار پخش نمی‌شود.',
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('تلاش دوباره')),
              ],
              if (_scenes.isEmpty && _error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('ابتدا یک سناریو بساز، سپس برای آن زمان تعیین کن.'),
                ),
              if (_automations.isEmpty && _scenes.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('هنوز زمان‌بندی‌ای نساخته‌ای.'),
                ),
              for (final automation in _automations)
                Card(
                  child: ListTile(
                    title: Text(_sceneName(automation)),
                    subtitle: Text(
                      '${toPersianDigits(automation.hour.toString().padLeft(2, '0'))}:'
                      '${toPersianDigits(automation.minute.toString().padLeft(2, '0'))}'
                      ' · ${_days(automation.weekdays)}',
                    ),
                    leading: Switch(
                      value: automation.enabled,
                      onChanged: _saving
                          ? null
                          : (enabled) => _mutate(
                              (current) => current
                                  .map(
                                    (item) => item.id == automation.id
                                        ? item.copyWith(
                                            enabled: enabled,
                                            clearLastHandledSlot: enabled,
                                          )
                                        : item,
                                  )
                                  .toList(),
                            ),
                    ),
                    trailing: PopupMenuButton<String>(
                      enabled: !_saving,
                      onSelected: (value) {
                        if (value == 'edit') _edit(automation);
                        if (value == 'delete') {
                          _mutate(
                            (current) => current
                                .where((item) => item.id != automation.id)
                                .toList(),
                          );
                        }
                      },
                      itemBuilder: (_) => const <PopupMenuEntry<String>>[
                        PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}

final class _AutomationEditor extends StatefulWidget {
  const _AutomationEditor({required this.scenes, this.automation});

  final List<ManualScene> scenes;
  final SceneAutomation? automation;

  @override
  State<_AutomationEditor> createState() => _AutomationEditorState();
}

final class _AutomationEditorState extends State<_AutomationEditor> {
  late String _sceneId;
  late TimeOfDay _time;
  late Set<int> _weekdays;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sceneId = widget.automation?.sceneId ?? widget.scenes.first.id;
    _time = TimeOfDay(
      hour: widget.automation?.hour ?? 8,
      minute: widget.automation?.minute ?? 0,
    );
    _weekdays = Set<int>.of(
      widget.automation?.weekdays ??
          const <int>{
            DateTime.saturday,
            DateTime.sunday,
            DateTime.monday,
            DateTime.tuesday,
            DateTime.wednesday,
            DateTime.thursday,
            DateTime.friday,
          },
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.automation == null ? 'زمان‌بندی جدید' : 'ویرایش زمان‌بندی'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: widget.scenes.any((scene) => scene.id == _sceneId)
                ? _sceneId
                : widget.scenes.first.id,
            decoration: const InputDecoration(labelText: 'سناریو'),
            items: <DropdownMenuItem<String>>[
              for (final scene in widget.scenes)
                DropdownMenuItem(value: scene.id, child: Text(scene.name)),
            ],
            onChanged: (value) => setState(() => _sceneId = value!),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule),
            label: Text(
              '${toPersianDigits(_time.hour.toString().padLeft(2, '0'))}:'
              '${toPersianDigits(_time.minute.toString().padLeft(2, '0'))}',
            ),
            onPressed: () async {
              final selected = await showTimePicker(
                context: context,
                initialTime: _time,
              );
              if (selected != null) setState(() => _time = selected);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: const <(int, String)>[
              (DateTime.saturday, 'ش'),
              (DateTime.sunday, 'ی'),
              (DateTime.monday, 'د'),
              (DateTime.tuesday, 'س'),
              (DateTime.wednesday, 'چ'),
              (DateTime.thursday, 'پ'),
              (DateTime.friday, 'ج'),
            ].map((item) => FilterChip(
              label: Text(item.$2),
              selected: _weekdays.contains(item.$1),
              onSelected: (selected) => setState(() {
                if (selected) _weekdays.add(item.$1);
                else _weekdays.remove(item.$1);
              }),
            )).toList(),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: () {
          if (_weekdays.isEmpty) {
            setState(() => _error = 'حداقل یک روز را انتخاب کن.');
            return;
          }
          Navigator.pop(
            context,
            SceneAutomation(
              id: widget.automation?.id ??
                  DateTime.now().microsecondsSinceEpoch.toString(),
              sceneId: _sceneId,
              hour: _time.hour,
              minute: _time.minute,
              weekdays: _weekdays,
              enabled: widget.automation?.enabled ?? true,
              lastHandledSlot: widget.automation?.lastHandledSlot,
            ),
          );
        },
        child: const Text('ذخیره'),
      ),
    ],
  );
}
