import 'package:flutter/material.dart';

import '../core/persian_digits.dart';
import 'color_control.dart';

final class ColorControl extends StatefulWidget {
  const ColorControl({required this.state, required this.enabled,
    required this.stale, required this.onChanged, required this.onRefresh, super.key});
  final DirectColorState? state;
  final bool enabled;
  final bool stale;
  final ValueChanged<HSVColor> onChanged;
  final VoidCallback onRefresh;
  @override
  State<ColorControl> createState() => _ColorControlState();
}

final class _ColorControlState extends State<ColorControl> {
  HSVColor? _draft;
  @override
  void didUpdateWidget(ColorControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state || !widget.enabled) _draft = null;
  }

  void _send(HSVColor color) {
    setState(() => _draft = null);
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = widget.state?.hsv;
    final shown = _draft ?? confirmed;
    final active = widget.enabled && !widget.stale && widget.state?.supportsColor == true;
    const presets = <String, double>{'قرمز': 0, 'نارنجی': 30, 'زرد': 60,
      'سبز': 120, 'آبی': 240, 'بنفش': 280};
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Expanded(child: Text('رنگ نور', style: TextStyle(fontWeight: FontWeight.w600))),
          if (shown != null) Semantics(label: _draft == null ? 'رنگ دریافت‌شده از وسیله' : 'پیش‌نمایش رنگ', child: Container(
            key: const ValueKey('confirmed-color'), width: 28, height: 28,
            decoration: BoxDecoration(color: shown.toColor(), shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.outline)),
          )),
        ]),
        if (confirmed == null) const Text('رنگ فعلی دریافت نشده'),
        if (widget.stale) Row(children: <Widget>[
          const Expanded(child: Text('رنگ نیاز به به‌روزرسانی دارد')),
          TextButton(onPressed: widget.onRefresh, child: const Text('دریافت رنگ')),
        ]),
        if (shown != null) ...<Widget>[
          Semantics(label: 'انتخاب رنگ از طیف', child: Stack(alignment: Alignment.center,
            children: <Widget>[
              Container(height: 18, margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(colors: <Color>[
                    Color(0xffff0000), Color(0xffffff00), Color(0xff00ff00),
                    Color(0xff00ffff), Color(0xff0000ff), Color(0xffff00ff), Color(0xffff0000),
                  ]))),
              // Physical spectrum and slider both run left-to-right, even in Persian.
              Directionality(textDirection: TextDirection.ltr, child: SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 18,
                  activeTrackColor: Colors.transparent, inactiveTrackColor: Colors.transparent,
                  disabledActiveTrackColor: Colors.transparent,
                  disabledInactiveTrackColor: Colors.transparent,
                  thumbColor: HSVColor.fromAHSV(1, shown.hue, 1, 1).toColor()),
                child: Slider(key: const ValueKey('color-hue'), min: 0, max: 360,
                  value: shown.hue,
                  semanticFormatterCallback: (value) => 'رنگ ${toPersianDigits(value.round())}',
                  onChanged: active ? (value) => setState(() =>
                    _draft = HSVColor.fromAHSV(1,value % 360,1,1)) : null,
                  onChangeEnd: active ? (value) =>
                    _send(HSVColor.fromAHSV(1,value % 360,1,1)) : null))),
            ])),
        ],
        Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
          for (final entry in presets.entries)
            ActionChip(label: Text(entry.key), avatar: CircleAvatar(
              backgroundColor: HSVColor.fromAHSV(1, entry.value, 1, 1).toColor()),
              onPressed: active ? () => _send(HSVColor.fromAHSV(1,entry.value,1,1)) : null),
          ActionChip(label: const Text('سفید'),
            onPressed: active ? () => _send(const HSVColor.fromAHSV(1,0,0,1)) : null),
        ]),
      ]),
    );
  }
}
