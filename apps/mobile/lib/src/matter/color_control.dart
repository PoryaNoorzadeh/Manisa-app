import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Raw ColorControl observations. Brightness belongs to LevelControl; it is
/// deliberately not mixed into the color preview or a color command.
final class DirectColorState {
  DirectColorState.fromMap(Map<Object?, Object?> raw)
      : values = Map<String, int?>.unmodifiable(_decode(raw));

  final Map<String, int?> values;
  static const limits = <String, int>{
    'capabilities': 65535, 'mode': 2, 'enhancedMode': 3,
    'hue': 254, 'saturation': 254, 'x': 65279, 'y': 65279,
    'enhancedHue': 65535,
  };

  static Map<String, int?> _decode(Map<Object?, Object?> raw) {
    final result = <String, int?>{};
    for (final entry in raw.entries) {
      final maximum = limits[entry.key];
      if (maximum == null) continue;
      final value = entry.value;
      if (value != null && (value is! int || value < 0 || value > maximum)) {
        throw const FormatException('invalid ColorControl attribute');
      }
      result[entry.key! as String] = value as int?;
    }
    return result;
  }

  int get capabilities => values['capabilities'] ?? 0;
  bool get supportsHueSaturation => capabilities & 1 != 0;
  bool get supportsXy => capabilities & 8 != 0;
  bool get supportsColor => supportsHueSaturation || supportsXy;

  DirectColorState merge(DirectColorState report) =>
      DirectColorState.fromMap(<String, int?>{...values, ...report.values});

  HSVColor? get hsv {
    final mode = values['enhancedMode'] ?? values['mode'];
    final saturation = values['saturation'];
    if ((mode == 0 || mode == 3) && supportsHueSaturation && saturation != null) {
      final hue = mode == 3 ? values['enhancedHue'] : values['hue'];
      if (hue == null) return null;
      return HSVColor.fromAHSV(1, (hue * 360 / (mode == 3 ? 65536 : 254)) % 360,
          saturation / 254, 1);
    }
    if (mode == 1 && supportsXy) {
      final x = values['x'];
      final y = values['y'];
      if (x == null || y == null || y == 0 || x + y > 65536) return null;
      return xyToHsv(x, y);
    }
    // Color temperature and incomplete observations have no invented RGB value.
    return null;
  }
}

final class DirectColorEvent {
  const DirectColorEvent({required this.nodeId, required this.endpoint,
    required this.report, this.stale = false});
  final int nodeId;
  final int endpoint;
  final DirectColorState report;
  final bool stale;

  factory DirectColorEvent.fromMap(Map<Object?, Object?> raw) {
    final node = raw['nodeId'];
    final endpoint = raw['endpoint'];
    final values = raw['values'];
    if (node is! int || endpoint is! int || endpoint <= 0 ||
        values is! Map<Object?, Object?> ||
        (raw['stale'] != null && raw['stale'] is! bool)) {
      throw const FormatException('invalid color report');
    }
    return DirectColorEvent(nodeId: node, endpoint: endpoint,
        report: DirectColorState.fromMap(values), stale: raw['stale'] == true);
  }
}

/// Standard sRGB/D65 conversion. Devices may clip to their physical gamut;
/// the UI always reads back the resulting device coordinates.
({int x, int y}) hsvToXy(HSVColor hsv) {
  final color = hsv.withValue(1).toColor();
  double linear(double value) => value <= 0.04045
      ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  final r = linear(color.r), g = linear(color.g), b = linear(color.b);
  final x = 0.4124564*r + 0.3575761*g + 0.1804375*b;
  final y = 0.2126729*r + 0.7151522*g + 0.0721750*b;
  final z = 0.0193339*r + 0.1191920*g + 0.9503041*b;
  final total = x+y+z;
  return (x: (x/total*65536).round().clamp(0,65279),
      y: (y/total*65536).round().clamp(1,65279));
}

HSVColor xyToHsv(int rawX, int rawY) {
  final x = rawX/65536, y = rawY/65536;
  final xx = x/y, zz = (1-x-y)/y;
  var r = math.max(0.0, 3.2404542*xx - 1.5371385 - 0.4985314*zz);
  var g = math.max(0.0, -0.9692660*xx + 1.8760108 + 0.0415560*zz);
  var b = math.max(0.0, 0.0556434*xx - 0.2040259 + 1.0572252*zz);
  final scale = math.max(1.0, math.max(r, math.max(g,b)));
  double gamma(double value) => value <= 0.0031308 ? 12.92*value
      : 1.055*math.pow(value,1/2.4)-0.055;
  r = gamma(r/scale); g = gamma(g/scale); b = gamma(b/scale);
  return HSVColor.fromColor(Color.fromARGB(255, (r*255).round().clamp(0,255),
      (g*255).round().clamp(0,255), (b*255).round().clamp(0,255))).withValue(1);
}
