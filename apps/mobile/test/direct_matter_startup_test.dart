import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';

void main() {
  testWidgets('restores live state without blocking onboarding on discovery',
      (tester) async {
    final controller = _Controller();
    await tester.pumpWidget(ManisaDirectApp(
      controller: controller,
      deviceStore: _Store(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saved switch'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(controller.discoveryCalls, 1);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

    // A manual refresh may hang on an offline node, but onboarding stays usable.
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(controller.discoveryCalls, 1);
    await tester.tap(find.text('Add Device'));
    await tester.pumpAndSettle();
    expect(find.text('Matter over Wi-Fi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.discovery.complete(<int>[]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final succeeds in <bool>[true, false]) {
    testWidgets('removal waits for remote confirmation: $succeeds', (tester) async {
      final controller = _Controller();
      controller.discovery.complete(<int>[1]);
      final store = _Store();
      await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pump();
      expect(store.removed, isFalse);
      expect(find.text('Saved switch'), findsOneWidget);
      if (succeeds) {
        controller.removal.complete();
      } else {
        controller.removal.completeError(PlatformException(code: 'matter_remove_failed'));
      }
      await tester.pumpAndSettle();
      expect(store.removed, succeeds);
      expect(find.text('Saved switch'), succeeds ? findsNothing : findsOneWidget);
      if (!succeeds) expect(find.textContaining('Remove failed'), findsOneWidget);
    });
  }

  testWidgets('discovery timeout is visible and permits retry', (tester) async {
    final controller = _Controller();
    await tester.pumpWidget(ManisaDirectApp(controller: controller, deviceStore: _Store()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not refresh Saved switch'), findsOneWidget);
    controller.discovery.complete(<int>[1]);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(controller.discoveryCalls, 2);
  });

  testWidgets('native initialization error is shown instead of endless loading',
      (tester) async {
    await tester.pumpWidget(ManisaDirectApp(
      controller: _Controller(initializationFails: true),
      deviceStore: _Store(),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('matter_initialization_failed'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Controller implements DirectMatterController {
  _Controller({this.initializationFails = false});

  final bool initializationFails;
  final discovery = Completer<List<int>>();
  final removal = Completer<void>();

  @override
  Future<void> removeDevice(int nodeId) => removal.future;
  int discoveryCalls = 0;

  @override
  Future<bool> isSupported() async {
    if (initializationFails) {
      throw PlatformException(
        code: 'matter_initialization_failed',
        message: 'Matter could not start',
      );
    }
    return true;
  }

  @override
  Stream<DirectMatterOnOffEvent> watchOnOff() => const Stream.empty();

  @override
  Future<List<int>> discoverOnOffEndpoints(int nodeId) {
    discoveryCalls++;
    return discovery.future;
  }

  @override
  Future<bool> readOnOff({required int nodeId, required int endpoint}) async =>
      true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements DirectDeviceStore {
  bool removed = false;
  @override
  Future<List<DirectMatterDevice>> load() async => const <DirectMatterDevice>[
        DirectMatterDevice(
          nodeId: 7,
          name: 'Saved switch',
          onOffEndpoints: <int>[1],
        ),
      ];

  @override
  Future<void> save(DirectMatterDevice device) async {}

  @override
  Future<void> remove(int nodeId) async { removed = true; }
}
