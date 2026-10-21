import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_app.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/onboarding_services.dart';

class Store implements DirectDeviceStore {
  final saved = <DirectMatterDevice>[];
  @override
  Future<List<DirectMatterDevice>> load() async => saved;
  @override
  Future<void> save(DirectMatterDevice d) async => saved.add(d);
  @override
  Future<void> remove(int nodeId) async {}
}

void main() {
  for (final (alreadyCommissioned, timeout, holdRetry) in [
    (false, false, false),
    (true, false, false),
    (false, true, false),
    (true, true, false),
    (false, false, true),
  ])
    testWidgets(
      'M14 cancel preserves successful pairing=$alreadyCommissioned timeout=$timeout holdRetry=$holdRetry',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        await tester.binding.setSurfaceSize(const Size(800, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const methods = MethodChannel('com.manisa/matter/methods');
        final firstAttempt = Completer<Object?>();
        final retryAttempt = Completer<Object?>();
        var calls = 0;
        var cancelled = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          methods,
          (call) async {
            if (call.method == 'currentWifi')
              return {'ssid': 'Home', 'frequency': 2412};
            if (call.method == 'commissionWifi') {
              calls++;
              if (calls == 1) return firstAttempt.future;
              if (holdRetry) return retryAttempt.future;
              return {
                'nodeId': 99,
                'onOffEndpoints': [1],
              };
            }
            if (call.method == 'cancelCommissioning') {
              cancelled++;
              if (alreadyCommissioned)
                firstAttempt.complete({
                  'nodeId': 99,
                  'onOffEndpoints': [1],
                });
              return alreadyCommissioned;
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            methods,
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            onboardingChannel,
            null,
          );
        });
        final store = Store();
        await tester.pumpWidget(
          MaterialApp(
            home: DirectMatterAddDeviceScreen(
              controller: const PlatformDirectMatterController(),
              deviceStore: store,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'MT:TEST');
        await tester.tap(find.text('ادامه'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ادامه'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('اتصال وسیله'));
        await tester.tap(find.text('اتصال وسیله'));
        await tester.pump();
        expect(calls, 1);
        expect(find.text('توقف اتصال'), findsOneWidget);
        if (timeout) {
          await tester.pump(const Duration(seconds: 141));
        } else {
          await tester.tap(find.text('توقف اتصال'));
        }
        await tester.pumpAndSettle();
        expect(cancelled, 1);
        if (!alreadyCommissioned) {
          if (holdRetry) await tester.pump(const Duration(seconds: 100));
          await tester.tap(find.text('اتصال وسیله'));
          await tester.pump();
          if (holdRetry) {
            await tester.pump(const Duration(seconds: 41));
            expect(cancelled, 1);
            retryAttempt.complete({
              'nodeId': 99,
              'onOffEndpoints': [1],
            });
          }
          await tester.pumpAndSettle();
          expect(calls, 2);
        }
        expect(store.saved.single.nodeId, 99);
        if (!alreadyCommissioned)
          firstAttempt.complete({
            'nodeId': 88,
            'onOffEndpoints': [1],
          });
        await tester.pumpAndSettle();
        expect(store.saved.length, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
}
