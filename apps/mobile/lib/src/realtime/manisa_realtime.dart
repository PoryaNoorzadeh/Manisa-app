import 'dart:convert';
import 'dart:io';

import '../data/models.dart';
import '../discovery/hub_discovery.dart';

final class ManisaRealtime {
  const ManisaRealtime(this._discovery);

  final HubDiscovery _discovery;

  Stream<ManisaEvent> connect() async* {
    final hub = await _discovery.discover();
    final uri = hub.replace(
      scheme: hub.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/v1/events',
      query: null,
      fragment: null,
    );
    final socket = await WebSocket.connect(uri.toString());
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
