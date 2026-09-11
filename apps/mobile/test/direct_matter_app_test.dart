import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';

void main() {
  testWidgets('offline state refresh does not block adding a device',
      (tester) async {
    final controller = _HangingRefreshController();

    await tester.pumpWidget(
      ManisaDirectApp(
        controller: controller,
        deviceStore: _MemoryDeviceStore(),
      ),
    );
    await tester.pump();

    expect(controller.refreshStarted, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final addDevice = find.widgetWithText(FloatingActionButton, 'Add Device');
    expect(addDevice, findsOneWidget);
    await tester.tap(addDevice);
    await tester.pumpAndSettle();

    expect(find.text('Matter over Wi-Fi'), findsOneWidget);
  });
}

final class _MemoryDeviceStore implements DirectDeviceStore {
  @override
  Future<List<DirectMatterDevice>> load() async => const <DirectMatterDevice>[
        DirectMatterDevice(
          nodeId: 1,
          name: 'Offline switch',
          onOffEndpoints: <int>[1],
        ),
      ];

  @override
  Future<void> remove(int nodeId) async {}

  @override
  Future<void> save(DirectMatterDevice device) async {}
}

final class _HangingRefreshController implements DirectMatterController {
  final Completer<List<int>> _refresh = Completer<List<int>>();
  bool refreshStarted = false;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<List<int>> discoverOnOffEndpoints(int nodeId) {
    refreshStarted = true;
    return _refresh.future;
  }

  @override
  Stream<DirectMatterOnOffEvent> watchOnOff() => const Stream.empty();

  @override
  Future<DirectMatterCommissionResult> commissionWifi({
    required String setupPayload,
    required String ssid,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<bool> readOnOff({required int nodeId, required int endpoint}) =>
      throw UnimplementedError();

  @override
  Future<void> removeDevice(int nodeId) => throw UnimplementedError();

  @override
  Future<void> setOnOff({
    required int nodeId,
    required int endpoint,
    required bool value,
  }) => throw UnimplementedError();

  @override
  Future<void> toggleOnOff({required int nodeId, required int endpoint}) =>
      throw UnimplementedError();
}
