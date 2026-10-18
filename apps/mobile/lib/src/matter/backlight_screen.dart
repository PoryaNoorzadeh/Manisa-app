import 'package:flutter/material.dart';

import '../design/manisa_brand.dart';
import '../design/manisa_localization.dart';
import 'backlight_policy.dart';
import 'direct_device_store.dart';
import 'room_store.dart';

class BacklightScreen extends StatefulWidget {
  const BacklightScreen({
    required this.store,
    required this.devices,
    required this.rooms,
    required this.apply,
    super.key,
  });
  final BacklightStore store;
  final List<DirectMatterDevice> Function() devices;
  final RoomCatalog Function() rooms;
  final Future<bool> Function(BacklightTarget, HSVColor) apply;
  @override
  State<BacklightScreen> createState() => _BacklightScreenState();
}

class _BacklightScreenState extends State<BacklightScreen> {
  BacklightPolicy _policy = const BacklightPolicy();
  bool _loading = true, _working = false;
  String? _error, _room;
  HSVColor? _draft;
  final Map<String, bool> _results = {};
  final Set<String> _attempted = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final policy = await widget.store.load();
      if (mounted)
        setState(() {
          _policy = policy;
          _error = null;
        });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'خواندن تنظیمات انجام نشد. دوباره تلاش کن.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save(BacklightPolicy next) async {
    try {
      await widget.store.save(next);
      if (!mounted) return false;
      setState(() {
        _policy = next;
        _error = null;
      });
      return true;
    } catch (_) {
      if (mounted)
        setState(() => _error = 'ذخیرهٔ تنظیمات انجام نشد. دوباره تلاش کن.');
      return false;
    }
  }

  Future<void> _choose() async {
    final selected = {..._policy.endpoints};
    final choices = [
      for (final device in widget.devices())
        for (final entry in device.colorCapabilities.entries)
          if (entry.value & 9 != 0) BacklightTarget(device, entry.key),
    ];
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppText(
                  'انتخاب کلیدها',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const AppText('خروجی‌های نور پس‌زمینه را مشخص کن.'),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final target in choices)
                        CheckboxListTile(
                          value: selected.contains(target.key),
                          title: Text(target.device.name),
                          subtitle: AppText('خروجی ${target.endpoint}'),
                          onChanged: (value) => update(() {
                            value == true
                                ? selected.add(target.key)
                                : selected.remove(target.key);
                          }),
                        ),
                      if (choices.isEmpty)
                        const AppText('هیچ کلیدی انتخاب نشده است.'),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const AppText('ذخیره'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _working = true);
      await _save(_policy.withEndpoints(result));
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _apply({bool retry = false}) async {
    final desired = _draft ?? _policy.colorForRoom(_room);
    if (desired == null || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final next = _room == null
        ? _policy.withHomeColor(desired)
        : _draft == null && !_policy.roomColors.containsKey(_room)
        ? _policy
        : _policy.withRoomColor(_room!, desired);
    if (!await _save(next)) {
      if (mounted) setState(() => _working = false);
      return;
    }
    final targets = next
        .targets(widget.devices(), widget.rooms(), roomId: _room)
        .where(
          (target) =>
              !retry ||
              (_attempted.contains(target.key) && _results[target.key] != true),
        )
        .toList();
    if (!retry) {
      _results.clear();
      _attempted
        ..clear()
        ..addAll(targets.map((t) => t.key));
    }
    for (final target in targets) {
      if (!mounted) break;
      bool ok = false;
      try {
        ok = await widget.apply(target, desired);
      } catch (_) {
        ok = false;
      }
      if (mounted) setState(() => _results[target.key] = ok);
    }
    if (mounted)
      setState(() {
        _working = false;
        _draft = null;
      });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _draft ?? _policy.colorForRoom(_room);
    final choices = widget.rooms().rooms;
    final targets = _policy.targets(
      widget.devices(),
      widget.rooms(),
      roomId: _room,
    );
    final copy = ManisaCopy.of(context);
    final failures = _results.values.where((ok) => !ok).length;
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(title: const AppText('نور پس‌زمینهٔ کلیدها')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            AppText(_error!),
                            TextButton(
                              onPressed: _working ? null : _load,
                              child: const AppText('تلاش دوباره'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Center(child: SwitchBacklightIcon(size: 56)),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    initialValue: _room ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr('رنگ این اتاق'),
                    ),
                    items: [
                      DropdownMenuItem(value: '', child: AppText('رنگ خانه')),
                      for (final room in choices)
                        DropdownMenuItem(
                          value: room.id,
                          child: Text(room.name),
                        ),
                    ],
                    onChanged: _working
                        ? null
                        : (value) => setState(() {
                            _room = value == '' ? null : value;
                            _draft = null;
                            _results.clear();
                            _attempted.clear();
                          }),
                  ),
                  const SizedBox(height: 16),
                  if (_room != null)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const AppText('استفاده از رنگ خانه'),
                      value: !_policy.roomColors.containsKey(_room),
                      onChanged: _working
                          ? null
                          : (follow) async {
                              setState(() => _working = true);
                              await _save(
                                _policy.withRoomColor(
                                  _room!,
                                  follow
                                      ? null
                                      : shown ??
                                            const HSVColor.fromAHSV(
                                              1,
                                              240,
                                              1,
                                              1,
                                            ),
                                ),
                              );
                              if (mounted)
                                setState(() {
                                  _working = false;
                                  _draft = null;
                                  _results.clear();
                                });
                            },
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: shown?.toColor(),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline
                                      .withValues(alpha: .3),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (shown == null)
                            const AppText(
                              'رنگ ذخیره نشده است.',
                              textAlign: TextAlign.center,
                            ),
                          const SizedBox(height: 12),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  height: 20,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.red,
                                        Colors.yellow,
                                        Colors.green,
                                        Colors.cyan,
                                        Colors.blue,
                                        Colors.purple,
                                        Colors.red,
                                      ],
                                    ),
                                  ),
                                ),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 20,
                                    activeTrackColor: Colors.transparent,
                                    inactiveTrackColor: Colors.transparent,
                                    thumbColor: shown?.toColor(),
                                  ),
                                  child: Slider(
                                    value: shown?.hue ?? 240,
                                    min: 0,
                                    max: 360,
                                    onChanged: _working
                                        ? null
                                        : (h) => setState(() {
                                            _draft = HSVColor.fromAHSV(
                                              1,
                                              h % 360,
                                              1,
                                              1,
                                            );
                                            _results.clear();
                                          }),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final hue in [
                                0.0,
                                30.0,
                                120.0,
                                180.0,
                                240.0,
                                280.0,
                              ])
                                Semantics(
                                  button: true,
                                  label: copy.number(hue.round()),
                                  child: IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      backgroundColor: HSVColor.fromAHSV(
                                        1,
                                        hue,
                                        1,
                                        1,
                                      ).toColor(),
                                    ),
                                    onPressed: _working
                                        ? null
                                        : () => setState(() {
                                            _draft = HSVColor.fromAHSV(
                                              1,
                                              hue,
                                              1,
                                              1,
                                            );
                                            _results.clear();
                                          }),
                                    icon: const Icon(
                                      Icons.circle_outlined,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ActionChip(
                                label: const AppText('سفید'),
                                onPressed: _working
                                    ? null
                                    : () => setState(() {
                                        _draft = const HSVColor.fromAHSV(
                                          1,
                                          0,
                                          0,
                                          1,
                                        );
                                        _results.clear();
                                      }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const SwitchBacklightIcon(),
                    title: const AppText('انتخاب کلیدها'),
                    subtitle: Text(
                      copy.count(targets.length, 'خروجی', 'outputs', 'مخارج'),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _working ? null : _choose,
                  ),
                  const AppText(
                    'رنگ فقط با لمس «اعمال رنگ» به کلیدها ارسال می‌شود.',
                  ),
                  const SizedBox(height: 20),
                  if (_working) const LinearProgressIndicator(),
                  if (_results.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          copy.language == 'en'
                              ? 'Confirmed: ${_results.values.where((v) => v).length} · Not confirmed: $failures'
                              : copy.language == 'ar'
                              ? 'مؤكد: ${copy.number(_results.values.where((v) => v).length)} · غير مؤكد: ${copy.number(failures)}'
                              : 'تأییدشده: ${copy.number(_results.values.where((v) => v).length)} · تأییدنشده: ${copy.number(failures)}',
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed:
                        _working ||
                            shown == null ||
                            targets.isEmpty ||
                            _error != null
                        ? null
                        : () => _apply(),
                    child: AppText(
                      _working ? 'اعمال رنگ در حال انجام است…' : 'اعمال رنگ',
                    ),
                  ),
                  if (failures > 0)
                    TextButton(
                      onPressed: _working ? null : () => _apply(retry: true),
                      child: const AppText('تلاش مجدد موارد تأییدنشده'),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }
}
