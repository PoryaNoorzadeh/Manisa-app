import 'dart:convert';
import 'dart:io';

import '../discovery/hub_discovery.dart';
import '../security/token_store.dart';
import 'models.dart';

abstract interface class ManisaApi {
  Future<void> pair({required String code, required String clientName});
  Future<List<Home>> listHomes();
  Future<List<Room>> listRooms(String homeId);
  Future<List<Device>> listDevices(String homeId);
  Future<DeviceDescriptor> deviceDescriptor(String deviceId);
  Future<List<DeviceState>> deviceStates(String deviceId);
  Future<Device> commissionMatterDevice({
    required String homeId,
    String? roomId,
    required String name,
    required String productType,
    required String transport,
    required String setupPayload,
    String wifiSsid = '',
    String wifiPassword = '',
    String threadDataset = '',
  });
  Future<void> executeCommand({
    required String deviceId,
    required int endpoint,
    required String capability,
    required String action,
    JsonMap params = const <String, Object?>{},
  });
}

final class HttpManisaApi implements ManisaApi {
  HttpManisaApi(
    this._discovery, {
    required TokenStore tokenStore,
    HttpClient? client,
  })  : _tokenStore = tokenStore,
        _client = client ?? HttpClient();

  final HubDiscovery _discovery;
  final TokenStore _tokenStore;
  final HttpClient _client;

  @override
  Future<void> pair({required String code, required String clientName}) async {
    final hub = await _discovery.discover();
    final request = await _client.postUrl(hub.resolve('/api/v1/pair'));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{'code': code, 'clientName': clientName}),
    );
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != HttpStatus.created) {
      throw ManisaApiException(response.statusCode, body);
    }
    final payload = jsonDecode(body) as Map<String, Object?>;
    final token = payload['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const ManisaApiException(500, 'pair response missing token');
    }
    await _tokenStore.write(token);
  }

  @override
  Future<List<Home>> listHomes() async =>
      _list('/api/v1/homes', Home.fromJson);

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
    final json = await _get(
      '/api/v1/devices/${Uri.encodeComponent(deviceId)}/descriptor',
    );
    return DeviceDescriptor.fromJson(json! as JsonMap);
  }

  @override
  Future<List<DeviceState>> deviceStates(String deviceId) async => _list(
        '/api/v1/devices/${Uri.encodeComponent(deviceId)}/state',
        DeviceState.fromJson,
      );

  @override
  Future<Device> commissionMatterDevice({
    required String homeId,
    String? roomId,
    required String name,
    required String productType,
    required String transport,
    required String setupPayload,
    String wifiSsid = '',
    String wifiPassword = '',
    String threadDataset = '',
  }) async {
    final hub = await _discovery.discover();
    final request = await _client.postUrl(
      hub.resolve('/api/v1/matter/commission'),
    );
    await _authorize(request);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'homeId': homeId,
        if (roomId != null && roomId.isNotEmpty) 'roomId': roomId,
        'name': name,
        'productType': productType,
        'transport': transport,
        'setupPayload': setupPayload,
        if (wifiSsid.isNotEmpty) 'wifiSsid': wifiSsid,
        if (wifiPassword.isNotEmpty) 'wifiPassword': wifiPassword,
        if (threadDataset.isNotEmpty) 'threadDataset': threadDataset,
      }),
    );
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != HttpStatus.created) {
      throw ManisaApiException(response.statusCode, body);
    }
    return Device.fromJson(jsonDecode(body) as JsonMap);
  }

  @override
  Future<void> executeCommand({
    required String deviceId,
    required int endpoint,
    required String capability,
    required String action,
    JsonMap params = const <String, Object?>{},
  }) async {
    final hub = await _discovery.discover();
    final request = await _client.postUrl(
      hub.resolve(
        '/api/v1/devices/${Uri.encodeComponent(deviceId)}/commands',
      ),
    );
    await _authorize(request);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'endpoint': endpoint,
        'capability': capability,
        'action': action,
        if (params.isNotEmpty) 'params': params,
      }),
    );
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
    final request = await _client.getUrl(hub.resolve(path));
    await _authorize(request);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ManisaApiException(response.statusCode, body);
    }
    return jsonDecode(body);
  }

  Future<void> _authorize(HttpClientRequest request) async {
    final token = await _tokenStore.read();
    if (token == null || token.isEmpty) {
      throw const ManisaApiException(401, 'hub is not paired');
    }
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
}

final class ManisaApiException implements Exception {
  const ManisaApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ManisaApiException($statusCode): $body';
}
