import 'dart:convert';
import 'dart:io';

import '../discovery/hub_discovery.dart';
import 'models.dart';

abstract interface class ManisaApi {
  Future<List<Home>> listHomes();
  Future<List<Room>> listRooms(String homeId);
  Future<List<Device>> listDevices(String homeId);
  Future<DeviceDescriptor> deviceDescriptor(String deviceId);
  Future<List<DeviceState>> deviceStates(String deviceId);
  Future<void> executeCommand({
    required String deviceId,
    required int endpoint,
    required String capability,
    required String action,
    JsonMap params = const <String, Object?>{},
  });
}

final class HttpManisaApi implements ManisaApi {
  HttpManisaApi(this._discovery, {HttpClient? client})
      : _client = client ?? HttpClient();

  final HubDiscovery _discovery;
  final HttpClient _client;

  @override
  Future<List<Home>> listHomes() async => _list('/api/v1/homes', Home.fromJson);

  @override
  Future<List<Room>> listRooms(String homeId) async => _list(
        '/api/v1/rooms?homeId=${Uri.encodeQueryComponent(homeId)}',
        Room.fromJson,
      );

  @override
  Future<List<Device>> listDevices(String homeId) async => _list(
        '/api/v1/devices?homeId=${Uri.encodeQueryComponent(homeId)}',
        Device.fromJson,
      );

  @override
  Future<DeviceDescriptor> deviceDescriptor(String deviceId) async {
    final json = await _get('/api/v1/devices/${Uri.encodeComponent(deviceId)}/descriptor');
    return DeviceDescriptor.fromJson(json! as JsonMap);
  }

  @override
  Future<List<DeviceState>> deviceStates(String deviceId) async => _list(
        '/api/v1/devices/${Uri.encodeComponent(deviceId)}/state',
        DeviceState.fromJson,
      );

  @override
  Future<void> executeCommand({
    required String deviceId,
    required int endpoint,
    required String capability,
    required String action,
    JsonMap params = const <String, Object?>{},
  }) async {
    final hub = await _discovery.discover();
    final uri = hub.resolve('/api/v1/devices/${Uri.encodeComponent(deviceId)}/commands');
    final request = await _client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, Object?>{
      'endpoint': endpoint,
      'capability': capability,
      'action': action,
      if (params.isNotEmpty) 'params': params,
    }));
    final response = await request.close();
    if (response.statusCode != HttpStatus.noContent) {
      final body = await utf8.decodeStream(response);
      throw ManisaApiException(response.statusCode, body);
    }
    await response.drain<void>();
  }

  Future<List<T>> _list<T>(
    String path,
    T Function(JsonMap json) decode,
  ) async {
    final value = await _get(path);
    return (value! as List<Object?>)
        .map((item) => decode(item! as JsonMap))
        .toList(growable: false);
  }

  Future<Object?> _get(String path) async {
    final hub = await _discovery.discover();
    final response = await (await _client.getUrl(hub.resolve(path))).close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ManisaApiException(response.statusCode, body);
    }
    return jsonDecode(body);
  }
}

final class ManisaApiException implements Exception {
  const ManisaApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ManisaApiException($statusCode): $body';
}
