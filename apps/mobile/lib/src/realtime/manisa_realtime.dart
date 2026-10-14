import 'dart:convert';
import 'dart:io';

import '../data/models.dart';
import '../discovery/hub_discovery.dart';
import '../security/token_store.dart';

final class ManisaRealtime {
  const ManisaRealtime(this._discovery, {required TokenStore tokenStore}) : _tokenStore = tokenStore;

  final HubDiscovery _discovery;
  final TokenStore _tokenStore;

  Stream<ManisaEvent> connect() async* {
    final hub = await _discovery.discover();
    final token = await _tokenStore.read();
    if (token == null || token.isEmpty) {
      throw StateError('hub is not paired');
    }
    final uri = hub.replace(
      scheme: hub.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/v1/events',
      query: null,
      fragment: null,
    );
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: <String, dynamic>{HttpHeaders.authorizationHeader: 'Bearer $token'},
    );
    try {
      await for (final message in socket) {
        if (message is! String) {
          continue;
        }
        final value = jsonDecode(message);
        if (value is Map<String, Object?>) {
          yield ManisaEvent.fromJson(value);
        }
      }
    } finally {
      await socket.close();
    }
  }
}
