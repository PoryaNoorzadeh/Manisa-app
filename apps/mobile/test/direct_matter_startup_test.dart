import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';

void main() {
  testWidgets('saved offline devices do not start native discovery at launch',
      (tester) async {
    final controller = _Controller();
    await tester.pumpWidget(ManisaDirectApp(
      controller: controller,
      deviceStore: _Store(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saved switch'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(controller.discoveryCalls, 0);

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
      false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements DirectDeviceStore {
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
  Future<void> remove(int nodeId) async {}
}
