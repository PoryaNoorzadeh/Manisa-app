import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/matter/direct_device_store.dart';
import 'package:manisa_mobile/src/matter/direct_matter_controller.dart';
import 'package:manisa_mobile/src/matter/home_profile_store.dart';
import 'package:manisa_mobile/src/matter/room_store.dart';

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

  group('RoomCatalog', () {
    test('round trips rooms and device assignments', () {
      final catalog = const RoomCatalog().addRoom(
        const ManisaRoom(id: 'living', name: 'پذیرایی'),
      ).assignDevice(7, 'living');

      final decoded = RoomCatalog.fromJson(catalog.toJson());

      expect(decoded.rooms.single.name, 'پذیرایی');
      expect(decoded.roomIdForDevice(7), 'living');
    });

    test('migrates stale assignments to unassigned', () {
      final decoded = RoomCatalog.fromJson(<String, Object?>{
        'version': 1,
        'rooms': <Object?>[
          <String, Object?>{'id': 'living', 'name': 'پذیرایی'},
        ],
        'deviceRooms': <String, Object?>{
          '7': 'deleted-room',
          '8': 'living',
        },
      });

      expect(decoded.roomIdForDevice(7), isNull);
      expect(decoded.roomIdForDevice(8), 'living');
    });

    test('removing a room atomically clears its assignments', () {
      final catalog = const RoomCatalog()
          .addRoom(const ManisaRoom(id: 'living', name: 'پذیرایی'))
          .assignDevice(7, 'living')
          .removeRoom('living');

      expect(catalog.rooms, isEmpty);
      expect(catalog.roomIdForDevice(7), isNull);
      expect(
        () => catalog.assignDevice(7, 'missing'),
        throwsArgumentError,
      );
    });

    test('moves rooms while preserving assignments', () {
      final catalog = const RoomCatalog(
        rooms: <ManisaRoom>[
          ManisaRoom(id: 'living', name: 'پذیرایی'),
          ManisaRoom(id: 'bedroom', name: 'اتاق خواب'),
          ManisaRoom(id: 'kitchen', name: 'آشپزخانه'),
        ],
        deviceRooms: <int, String>{7: 'living'},
      ).moveRoom('living', 1);

      expect(
        catalog.rooms.map((room) => room.id),
        <String>['bedroom', 'living', 'kitchen'],
      );
      expect(catalog.roomIdForDevice(7), 'living');
      expect(identical(catalog.moveRoom('bedroom', -1), catalog), isTrue);
      expect(() => catalog.moveRoom('missing', 1), throwsArgumentError);
    });
  });

  group('ManisaHomeProfile', () {
    test('defaults legacy installs and round trips a custom name', () {
      expect(const ManisaHomeProfile().name, 'خانهٔ من');

      final renamed = const ManisaHomeProfile().rename('  خانهٔ پوریا  ');
      final decoded = ManisaHomeProfile.fromJson(renamed.toJson());

      expect(decoded.name, 'خانهٔ پوریا');
      expect(() => renamed.rename('   '), throwsArgumentError);
      expect(
        () => ManisaHomeProfile.fromJson(<String, Object?>{'name': ''}),
        throwsFormatException,
      );
    });
  });
}
