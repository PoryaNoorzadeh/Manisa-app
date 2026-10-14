import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/design/manisa_theme.dart';
import 'package:manisa_mobile/src/matter/device_summary_card.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';

void main() {
  const device = DirectMatterDevice(nodeId: 7, name: 'کلید پذیرایی',
    onOffEndpoints: [1, 2, 3]);

  testWidgets('summary distinguishes unknown outputs from confirmed off and stale', (tester) async {
    Future<void> show(bool unavailable) => tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DeviceSummaryCard(device: device,
        states: const {'7:1': true, '7:2': false}, unavailable: unavailable,
        availability: const Text('ارتباط'), menu: const SizedBox(),
        onOpen: () {}, onRefresh: () {}))));
    await show(false);
    expect(find.text('۱ از ۳ خروجی روشن · ۱ نامشخص'), findsOneWidget);
    await show(true);
    expect(find.text('آخرین وضعیت: ۱ از ۳ خروجی روشن · ۱ نامشخص'), findsOneWidget);
    expect(find.text('تلاش دوباره'), findsOneWidget);
  });

  testWidgets('summary actions wrap at 360dp and 200 percent Persian text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = 0;
    var refreshed = 0;
    await tester.pumpWidget(MaterialApp(theme: ManisaTheme.light,
      home: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Directionality(textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: DeviceSummaryCard(
            device: device.copyWith(name: 'کلید چراغ‌های پذیرایی و آشپزخانه'),
            roomName: 'پذیرایی و آشپزخانه', states: const {}, unavailable: true,
            availability: const Text('در دسترس نیست'),
            menu: IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
            onOpen: () => opened++, onRefresh: () => refreshed++,
          )))))));
    await tester.pumpAndSettle();
    expect(find.text('وضعیت ۳ خروجی دریافت نشده'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-device-7')));
    await tester.tap(find.text('تلاش دوباره'));
    expect(opened, 1);
    expect(refreshed, 1);
    expect(tester.takeException(), isNull);
  });
}
