import 'package:flutter/material.dart';

import '../design/color_wheel.dart';
import '../design/manisa_localization.dart';
import 'color_control.dart';

final class ColorControl extends StatefulWidget {
  const ColorControl({
    required this.state,
    required this.enabled,
    required this.stale,
    required this.onChanged,
    required this.onRefresh,
    this.busy = false,
    super.key,
  });
  final DirectColorState? state;
  final bool enabled;
  final bool busy;
  final bool stale;
  final ValueChanged<HSVColor> onChanged;
  final VoidCallback onRefresh;
  @override
  State<ColorControl> createState() => _ColorControlState();
}

final class _ColorControlState extends State<ColorControl> {
  HSVColor? _draft;
  bool _dragging = false;
  @override
  void didUpdateWidget(ColorControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.stale) {
      _draft = null;
      _dragging = false;
    } else if (!_dragging &&
        (!widget.busy && (oldWidget.state != widget.state || oldWidget.busy))) {
      _draft = null;
    }
  }

  void _send(HSVColor color) {
    setState(() {
      _dragging = false;
      _draft = color;
    });
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = widget.state?.hsv;
    final shown = _draft ?? confirmed;
    final active =
        widget.enabled && !widget.stale && widget.state?.supportsColor == true;
    const presets = <String, double>{
      'قرمز': 0,
      'نارنجی': 30,
      'زرد': 60,
      'سبز': 120,
      'آبی': 240,
      'بنفش': 280,
    };
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: AppText(
                  'رنگ نور',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (confirmed != null)
                Semantics(
                  label: context.tr('رنگ دریافت‌شده از وسیله'),
                  child: Container(
                    key: const ValueKey('confirmed-color'),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: confirmed.toColor(),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (confirmed == null) const AppText('رنگ فعلی دریافت نشده'),
          if (widget.stale)
            Row(
              children: <Widget>[
                const Expanded(child: AppText('رنگ نیاز به به‌روزرسانی دارد')),
                TextButton(
                  onPressed: widget.onRefresh,
                  child: const AppText('دریافت رنگ'),
                ),
              ],
            ),
          if (shown != null) ...<Widget>[
            Center(
              child: ColorWheel(
                key: const ValueKey('color-wheel'),
                value: shown,
                enabled: active,
                semanticLabel: context.tr('انتخاب رنگ از طیف'),
                onChanged: (color) => setState(() {
                  _dragging = true;
                  _draft = color;
                }),
                onChangeEnd: _send,
                onCancel: () => setState(() {
                  _dragging = false;
                  _draft = null;
                }),
              ),
            ),
            if (_draft != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    key: const ValueKey('color-preview'),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: shown.toColor(),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const AppText('پیش‌نمایش رنگ'),
                ],
              ),
            if (widget.busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final entry in presets.entries)
                ActionChip(
                  label: AppText(entry.key),
                  avatar: CircleAvatar(
                    backgroundColor: HSVColor.fromAHSV(
                      1,
                      entry.value,
                      1,
                      1,
                    ).toColor(),
                  ),
                  onPressed: active
                      ? () => _send(HSVColor.fromAHSV(1, entry.value, 1, 1))
                      : null,
                ),
              ActionChip(
                label: const AppText('سفید'),
                onPressed: active
                    ? () => _send(const HSVColor.fromAHSV(1, 0, 0, 1))
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
