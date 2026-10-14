import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/device_share_screen.dart';
import 'package:manisa_mobile/src/matter/onboarding_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('credentials are isolated by exact SSID and can be forgotten', () async {
    const store = WifiCredentialStore();
    await store.remember('Home', 'secret-a');
    await store.remember('home', 'secret-b');
    expect(await store.password('Home'), 'secret-a');
    expect(await store.password('home'), 'secret-b');
    expect(await store.lastSsid(), 'home');
    await store.forget('Home');
    expect(await store.password('Home'), isNull);
    expect(await store.lastSsid(), 'home');
    await store.forget('home');
    expect(await store.lastSsid(), isNull);
  });

  test('open networks retain empty passwords without confusing a missing entry', () async {
    const store = WifiCredentialStore();
    await store.remember('Guest', '');
    expect(await store.password('Guest'), '');
    expect(await store.password('Other'), isNull);
  });

  test('error UI never echoes platform details or credentials', () {
    final error = PlatformException(code: 'unknown', message: 'secret-password');
    expect(onboardingError(error), isNot(contains('secret-password')));
    expect(onboardingError(PlatformException(code: 'device_mismatch')), contains('متعلق'));
  });

  testWidgets('sharing requires explicit action and displays temporary QR', (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(onboardingChannel, (call) async {
      expect(call.method, 'openSharingWindow');
      calls++;
      return <String, Object?>{'qrCode': 'MT:TEST', 'expiresAt': DateTime.now().millisecondsSinceEpoch + 2000};
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(onboardingChannel, null));
    await tester.pumpWidget(const MaterialApp(home: DeviceShareScreen(nodeId: 7, name: 'چراغ')));
    expect(calls, 0);
    await tester.tap(find.text('ساخت کد موقت'));
    await tester.pump();
    await tester.pump();
    expect(calls, 1);
    expect(find.textContaining('اعتبار کد'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
