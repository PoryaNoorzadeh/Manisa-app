import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';

void main() {
  group('DirectMatterCommissionResult', () {
    test('decodes node and endpoints', () {
      final result = DirectMatterCommissionResult.fromMap(<Object?, Object?>{
        'nodeId': 42,
        'onOffEndpoints': <Object?>[1, 2, 3],
      });

      expect(result.nodeId, 42);
      expect(result.onOffEndpoints, <int>[1, 2, 3]);
    });

    test('rejects malformed endpoint data', () {
      expect(
        () => DirectMatterCommissionResult.fromMap(<Object?, Object?>{
          'nodeId': 42,
          'onOffEndpoints': <Object?>[1, '2'],
        }),
        throwsFormatException,
      );
    });
  });

  group('DirectMatterOnOffEvent', () {
    test('decodes realtime state event', () {
      final event = DirectMatterOnOffEvent.fromMap(<Object?, Object?>{
        'nodeId': 9,
        'endpoint': 2,
        'value': true,
      });

      expect(event.nodeId, 9);
      expect(event.endpoint, 2);
      expect(event.value, isTrue);
    });
  });

  group('DirectMatterDevice', () {
    test('round trips JSON metadata', () {
      const device = DirectMatterDevice(
        nodeId: 7,
        name: 'Living Room Switch',
        onOffEndpoints: <int>[1, 2, 3],
        channelNames: <int, String>{1: 'لوستر', 2: 'دیوار'},
      );

      final decoded = DirectMatterDevice.fromJson(device.toJson());

      expect(decoded.nodeId, device.nodeId);
      expect(decoded.name, device.name);
      expect(decoded.onOffEndpoints, device.onOffEndpoints);
      expect(decoded.channelNames, device.channelNames);
      expect(decoded.channelName(1, 0), 'لوستر');
      expect(decoded.channelName(3, 2), 'خروجی 3');
    });
    test('loads legacy JSON without output names', () {
      final decoded = DirectMatterDevice.fromJson(<String, Object?>{
        'nodeId': 8,
        'name': 'Legacy switch',
        'onOffEndpoints': <Object?>[11, 12],
      });
      expect(decoded.channelNames, isEmpty);
      expect(decoded.channelName(12, 1), 'خروجی 2');
    });

    test('keeps names bound to endpoint when discovery order changes', () {
      const device = DirectMatterDevice(
        nodeId: 9,
        name: 'Switch',
        onOffEndpoints: <int>[1, 2],
        channelNames: <int, String>{1: 'راست', 2: 'چپ'},
      );
      final reordered = device.copyWith(onOffEndpoints: <int>[2, 1]);
      expect(reordered.channelName(2, 0), 'چپ');
      expect(reordered.channelName(1, 1), 'راست');
    });
  });
}
