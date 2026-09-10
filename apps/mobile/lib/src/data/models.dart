typedef JsonMap = Map<String, Object?>;

final class Home {
  const Home({required this.id, required this.name});

  final String id;
  final String name;

  factory Home.fromJson(JsonMap json) => Home(
        id: json['id']! as String,
        name: json['name']! as String,
      );
}

final class Room {
  const Room({required this.id, required this.homeId, required this.name});

  final String id;
  final String homeId;
  final String name;

  factory Room.fromJson(JsonMap json) => Room(
        id: json['id']! as String,
        homeId: json['homeId']! as String,
        name: json['name']! as String,
      );
}

final class Device {
  const Device({
    required this.id,
    required this.homeId,
    required this.name,
    required this.productType,
    required this.transport,
    this.roomId,
  });

  final String id;
  final String homeId;
  final String? roomId;
  final String name;
  final String productType;
  final String transport;

  factory Device.fromJson(JsonMap json) => Device(
        id: json['id']! as String,
        homeId: json['homeId']! as String,
        roomId: json['roomId'] as String?,
        name: json['name']! as String,
        productType: json['productType']! as String,
        transport: json['transport']! as String,
      );
}

final class CapabilityDescriptor {
  const CapabilityDescriptor({
    required this.id,
    required this.readable,
    required this.writable,
    required this.metadata,
  });

  final String id;
  final bool readable;
  final bool writable;
  final JsonMap metadata;

  factory CapabilityDescriptor.fromJson(JsonMap json) => CapabilityDescriptor(
        id: json['id']! as String,
        readable: json['readable']! as bool,
        writable: json['writable']! as bool,
        metadata: (json['metadata'] as JsonMap?) ?? const <String, Object?>{},
      );
}

final class EndpointDescriptor {
  const EndpointDescriptor({
    required this.id,
    required this.name,
    required this.capabilities,
  });

  final int id;
  final String name;
  final List<CapabilityDescriptor> capabilities;

  factory EndpointDescriptor.fromJson(JsonMap json) => EndpointDescriptor(
        id: json['id']! as int,
        name: json['name']! as String,
        capabilities: (json['capabilities']! as List<Object?>)
            .map((value) => CapabilityDescriptor.fromJson(value! as JsonMap))
            .toList(growable: false),
      );
}

final class DeviceDescriptor {
  const DeviceDescriptor({
    required this.productType,
    required this.displayName,
    required this.category,
    required this.endpoints,
  });

  final String productType;
  final String displayName;
  final String category;
  final List<EndpointDescriptor> endpoints;

  factory DeviceDescriptor.fromJson(JsonMap json) => DeviceDescriptor(
        productType: json['productType']! as String,
        displayName: json['displayName']! as String,
        category: json['category']! as String,
        endpoints: (json['endpoints']! as List<Object?>)
            .map((value) => EndpointDescriptor.fromJson(value! as JsonMap))
            .toList(growable: false),
      );
}

final class DeviceState {
  const DeviceState({
    required this.deviceId,
    required this.endpoint,
    required this.capability,
    required this.value,
  });

  final String deviceId;
  final int endpoint;
  final String capability;
  final Object? value;

  String get key => '$endpoint:$capability';

  factory DeviceState.fromJson(JsonMap json) => DeviceState(
        deviceId: json['deviceId']! as String,
        endpoint: json['endpoint']! as int,
        capability: json['capability']! as String,
        value: json['value'],
      );
}

final class ManisaEvent {
  const ManisaEvent({
    required this.type,
    required this.deviceId,
    required this.endpoint,
    required this.capability,
    required this.value,
  });

  final String type;
  final String deviceId;
  final int endpoint;
  final String capability;
  final Object? value;

  factory ManisaEvent.fromJson(JsonMap json) => ManisaEvent(
        type: json['type']! as String,
        deviceId: json['deviceId']! as String,
        endpoint: json['endpoint']! as int,
        capability: json['capability']! as String,
        value: json['value'],
      );
}
