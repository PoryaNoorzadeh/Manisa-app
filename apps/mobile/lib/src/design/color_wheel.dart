import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hue around the circle, saturation from white at the center to the rim.
/// Pointer movement only previews; a completed gesture commits exactly once.
class ColorWheel extends StatefulWidget {
  const ColorWheel({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.semanticLabel,
    this.onCancel,
    this.enabled = true,
    super.key,
  });

  final HSVColor value;
  final bool enabled;
  final String semanticLabel;
  final ValueChanged<HSVColor> onChanged;
  final ValueChanged<HSVColor> onChangeEnd;
  final VoidCallback? onCancel;

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  HSVColor? _gestureColor;
  int _gestureRevision = 0;
  bool _focused = false;
  static const _inset = 12.0;

  @override
  void didUpdateWidget(ColorWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _gestureColor = null;
  }

  HSVColor _colorAt(Offset position, Size size) {
    final offset = position - size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _inset;
    return HSVColor.fromAHSV(
      1,
      (math.atan2(offset.dy, offset.dx) * 180 / math.pi + 360) % 360,
      (offset.distance / radius).clamp(0.0, 1.0),
      1,
    );
  }

  void _start(Offset position, Size size) {
    if (!widget.enabled ||
        (position - size.center(Offset.zero)).distance > size.shortestSide / 2)
      return;
    _gestureRevision++;
    _gestureColor = _colorAt(position, size);
    widget.onChanged(_gestureColor!);
  }

  void _update(Offset position, Size size) {
    if (!widget.enabled || _gestureColor == null) return;
    _gestureRevision++;
    _gestureColor = _colorAt(position, size);
    widget.onChanged(_gestureColor!);
  }

  void _finish() {
    final color = _gestureColor;
    _gestureRevision++;
    _gestureColor = null;
    if (widget.enabled && color != null) widget.onChangeEnd(color);
  }

  void _cancelPointer() {
    _gestureRevision++;
    if (_gestureColor == null) return;
    _gestureColor = null;
    widget.onCancel?.call();
  }

  void _cancel() {
    // A tap also cancels the competing pan recognizer. Let its tap-up
    // commit synchronously before treating a lost gesture as cancellation.
    final revision = _gestureRevision;
    Future.microtask(() {
      if (!mounted || revision != _gestureRevision || _gestureColor == null)
        return;
      _gestureColor = null;
      widget.onCancel?.call();
    });
  }

  void _step({double hue = 0, double saturation = 0}) {
    final next = widget.value
        .withHue((widget.value.hue + hue + 360) % 360)
        .withSaturation((widget.value.saturation + saturation).clamp(0.0, 1.0))
        .withValue(1);
    widget.onChanged(next);
    widget.onChangeEnd(next);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticLabel,
    enabled: widget.enabled,
    value:
        '${widget.value.hue.round()}°, ${(widget.value.saturation * 100).round()}%',
    increasedValue: widget.enabled
        ? '${((widget.value.hue + 5) % 360).round()}°, ${(widget.value.saturation * 100).round()}%'
        : null,
    decreasedValue: widget.enabled
        ? '${((widget.value.hue - 5 + 360) % 360).round()}°, ${(widget.value.saturation * 100).round()}%'
        : null,
    onIncrease: widget.enabled ? () => _step(hue: 5) : null,
    onDecrease: widget.enabled ? () => _step(hue: -5) : null,
    child: Focus(
      canRequestFocus: widget.enabled,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (_, event) {
        if (!widget.enabled || event is! KeyDownEvent)
          return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _step(hue: 5);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _step(hue: -5);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _step(saturation: .05);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _step(saturation: -.05);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 264, maxHeight: 264),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return Listener(
                onPointerCancel: (_) => _cancelPointer(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onPanDown: widget.enabled
                      ? (details) => _start(details.localPosition, size)
                      : null,
                  onTapUp: widget.enabled ? (_) => _finish() : null,
                  onPanStart: widget.enabled
                      ? (details) {
                          if (_gestureColor == null)
                            _start(details.localPosition, size);
                          _update(details.localPosition, size);
                        }
                      : null,
                  onPanUpdate: widget.enabled
                      ? (details) => _update(details.localPosition, size)
                      : null,
                  onPanEnd: widget.enabled ? (_) => _finish() : null,
                  onPanCancel: _cancel,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _WheelPainter(
                        widget.value,
                        widget.enabled,
                        _focused,
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.value, this.enabled, this.focused, this.focusColor);
  final HSVColor value;
  final bool enabled, focused;
  final Color focusColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _ColorWheelState._inset;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xffff0000),
            Color(0xffffff00),
            Color(0xff00ff00),
            Color(0xff00ffff),
            Color(0xff0000ff),
            Color(0xffff00ff),
            Color(0xffff0000),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00ffffff)],
        ).createShader(rect),
    );
    if (!enabled)
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = const Color(0x99eeeeee),
      );
    if (focused)
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = focusColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    final angle = value.hue * math.pi / 180;
    final marker =
        center +
        Offset(math.cos(angle), math.sin(angle)) * radius * value.saturation;
    canvas.drawCircle(marker, 10, Paint()..color = const Color(0x66000000));
    canvas.drawCircle(marker, 8, Paint()..color = value.withValue(1).toColor());
    canvas.drawCircle(
      marker,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      value != oldDelegate.value ||
      enabled != oldDelegate.enabled ||
      focused != oldDelegate.focused ||
      focusColor != oldDelegate.focusColor;
}
