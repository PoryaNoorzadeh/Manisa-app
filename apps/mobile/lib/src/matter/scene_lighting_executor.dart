import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'color_control.dart';
import 'direct_device_store.dart';
import 'direct_matter_controller.dart';
import 'manual_scene.dart';

bool sceneActionSupported(SceneAction action, DirectMatterDevice device) =>
    device.nodeId == action.nodeId && device.onOffEndpoints.contains(action.endpoint) &&
    (action.level == null || device.levelEndpoints.contains(action.endpoint)) &&
    (action.hue == null || ((device.colorCapabilities[action.endpoint] ?? 0) & 9) != 0);

/// One deadline covers all commands and readbacks. A timed-out native request
/// may complete, but this executor never sends a later command after timeout.
Future<bool> executeSceneLighting({required SceneAction action,
  required DirectMatterDevice device, required DirectMatterController controller,
  required bool Function() active,
  Duration budget = const Duration(seconds:28),
}) async {
  SceneAction.fromJson(action.toJson());
  if (!sceneActionSupported(action, device) ||
      (action.level != null && controller is! LevelControlController) ||
      (action.hue != null && controller is! ColorControlController)) {
    throw StateError('scene capability unavailable');
  }
  final clock = Stopwatch()..start();
  Future<T> step<T>(Future<T> Function() operation) async {
    if (!active()) throw StateError('scene target unavailable');
    final remaining = budget - clock.elapsed;
    if (remaining <= Duration.zero) throw TimeoutException('scene deadline');
    final result = await operation().timeout(remaining);
    if (!active()) throw StateError('scene target unavailable');
    return result;
  }
  await step(() => controller.setOnOff(nodeId:action.nodeId,endpoint:action.endpoint,value:action.on));
  if (action.level != null) {
    await step(() => (controller as LevelControlController).setLevel(
      nodeId:action.nodeId,endpoint:action.endpoint,level:action.level!));
  }
  final hs = ((device.colorCapabilities[action.endpoint] ?? 0) & 1) != 0;
  final color = action.hue == null ? null : HSVColor.fromAHSV(1,
    action.hue! * 360 / 254 % 360,action.saturation! / 254,1);
  final xy = color == null ? null : hsvToXy(color);
  if (color != null) {
    await step(() => (controller as ColorControlController).setColor(
      nodeId:action.nodeId,endpoint:action.endpoint,mode:hs?'hs':'xy',
      first:hs?action.hue!:xy!.x,second:hs?action.saturation!:xy!.y));
  }
  var matched = await step(() => controller.readOnOff(nodeId:action.nodeId,endpoint:action.endpoint)) == action.on;
  if (action.level != null) {
    final levels = await step(() => (controller as LevelControlController).readLevels(action.nodeId));
    matched = matched && levels[action.endpoint] == action.level;
  }
  if (color != null) {
    final colors = await step(() => (controller as ColorControlController).readColors(action.nodeId));
    final actual = colors[action.endpoint];
    final mode = actual?.values['enhancedMode'] ?? actual?.values['mode'];
    bool colorMatches = false;
    if (hs && (mode == 0 || mode == 3) && actual?.hsv != null) {
      final observed = actual!.hsv!;
      final delta = (observed.hue - color.hue).abs();
      colorMatches = (observed.saturation - color.saturation).abs() <= 2/254 &&
        (action.saturation == 0 || math.min(delta,360-delta) <= 3);
    } else if (!hs && mode == 1 && actual != null) {
      final x = actual.values['x']; final y = actual.values['y'];
      colorMatches = x != null && y != null && (x-xy!.x).abs() <= 2 && (y-xy.y).abs() <= 2;
    }
    matched = matched && colorMatches;
  }
  return matched;
}
