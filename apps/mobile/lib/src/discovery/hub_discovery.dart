import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

abstract interface class HubDiscovery {
  Future<Uri> discover();
}

final class ConfiguredHubDiscovery implements HubDiscovery {
  const ConfiguredHubDiscovery(this._hubUri);

  final Uri _hubUri;

  @override
  Future<Uri> discover() async => _hubUri;
}

final class MdnsHubDiscovery implements HubDiscovery {
  MdnsHubDiscovery({required Uri fallback}) : _fallback = fallback;

  static const _service = '_manisa._tcp.local';
  final Uri _fallback;
  Uri? _cached;

  @override
  Future<Uri> discover() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }

    final client = MDnsClient();
    try {
      await client.start();
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_service),
        timeout: const Duration(seconds: 3),
      )) {
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: const Duration(seconds: 3),
        )) {
          final uri = Uri(
            scheme: 'http',
            host: srv.target.endsWith('.')
                ? srv.target.substring(0, srv.target.length - 1)
                : srv.target,
            port: srv.port,
          );
          _cached = uri;
          return uri;
        }
      }
    } on Object {
      // Development/emulator fallback remains available when multicast is blocked.
    } finally {
      client.stop();
    }

    return _fallback;
  }

  void invalidate() => _cached = null;
}
