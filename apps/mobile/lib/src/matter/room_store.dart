import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class ManisaRoom {
  const ManisaRoom({required this.id, required this.name});

  final String id;
  final String name;

  ManisaRoom copyWith({String? name}) => ManisaRoom(
        id: id,
        name: name ?? this.name,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
      };

  factory ManisaRoom.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty) {
      throw const FormatException('invalid Manisa room');
    }
    return ManisaRoom(id: id, name: name.trim());
  }
}

final class RoomCatalog {
  const RoomCatalog({
    this.rooms = const <ManisaRoom>[],
    this.deviceRooms = const <int, String>{},
  });

  final List<ManisaRoom> rooms;
  final Map<int, String> deviceRooms;

  String? roomIdForDevice(int nodeId) => deviceRooms[nodeId];

  RoomCatalog addRoom(ManisaRoom room) => RoomCatalog(
        rooms: List<ManisaRoom>.unmodifiable(<ManisaRoom>[...rooms, room]),
        deviceRooms: deviceRooms,
      );

  RoomCatalog renameRoom(String roomId, String name) => RoomCatalog(
        rooms: List<ManisaRoom>.unmodifiable(
          rooms
              .map((room) => room.id == roomId ? room.copyWith(name: name) : room)
              .toList(growable: false),
        ),
        deviceRooms: deviceRooms,
      );

  RoomCatalog removeRoom(String roomId) => RoomCatalog(
        rooms: List<ManisaRoom>.unmodifiable(
          rooms.where((room) => room.id != roomId),
        ),
        deviceRooms: Map<int, String>.unmodifiable(
          Map<int, String>.of(deviceRooms)
            ..removeWhere((_, assignedRoomId) => assignedRoomId == roomId),
        ),
      );

  RoomCatalog assignDevice(int nodeId, String? roomId) {
    if (roomId != null && !rooms.any((room) => room.id == roomId)) {
      throw ArgumentError.value(roomId, 'roomId', 'unknown room');
    }
    final assignments = Map<int, String>.of(deviceRooms);
    if (roomId == null) {
      assignments.remove(nodeId);
    } else {
      assignments[nodeId] = roomId;
    }
    return RoomCatalog(
      rooms: rooms,
      deviceRooms: Map<int, String>.unmodifiable(assignments),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'rooms': rooms.map((room) => room.toJson()).toList(growable: false),
        'deviceRooms': deviceRooms.map(
          (nodeId, roomId) => MapEntry(nodeId.toString(), roomId),
        ),
      };

  factory RoomCatalog.fromJson(Map<String, Object?> json) {
    final rawRooms = json['rooms'];
    final rawAssignments = json['deviceRooms'];
    if (rawRooms is! List<Object?> ||
        (rawAssignments != null && rawAssignments is! Map<String, Object?>)) {
      throw const FormatException('invalid room catalog');
    }
    final rooms = rawRooms.map((value) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('invalid room entry');
      }
      return ManisaRoom.fromJson(value);
    }).toList(growable: false);
    if (rooms.map((room) => room.id).toSet().length != rooms.length) {
      throw const FormatException('duplicate room id');
    }
    final roomIds = rooms.map((room) => room.id).toSet();
    final assignments = <int, String>{};
    for (final entry
        in (rawAssignments as Map<String, Object?>? ?? const {}).entries) {
      final nodeId = int.tryParse(entry.key);
      final roomId = entry.value;
      if (nodeId == null || roomId is! String) {
        throw const FormatException('invalid room assignment');
      }
      // Stale assignments are safely migrated to "unassigned".
      if (roomIds.contains(roomId)) assignments[nodeId] = roomId;
    }
    return RoomCatalog(
      rooms: List<ManisaRoom>.unmodifiable(rooms),
      deviceRooms: Map<int, String>.unmodifiable(assignments),
    );
  }
}

abstract interface class RoomStore {
  Future<RoomCatalog> load();
  Future<void> save(RoomCatalog catalog);
}

final class EmptyRoomStore implements RoomStore {
  const EmptyRoomStore();

  @override
  Future<RoomCatalog> load() async => const RoomCatalog();

  @override
  Future<void> save(RoomCatalog catalog) async {}
}

final class PreferencesRoomStore implements RoomStore {
  PreferencesRoomStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _key = 'manisa_room_catalog_v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<RoomCatalog> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const RoomCatalog();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const RoomCatalog();
      return RoomCatalog.fromJson(decoded);
    } on FormatException {
      return const RoomCatalog();
    }
  }

  @override
  Future<void> save(RoomCatalog catalog) =>
      _preferences.setString(_key, jsonEncode(catalog.toJson()));
}
