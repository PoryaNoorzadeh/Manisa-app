abstract interface class HubDiscovery {
  Future<Uri> discover();
}

final class ConfiguredHubDiscovery implements HubDiscovery {
  const ConfiguredHubDiscovery(this._hubUri);

  final Uri _hubUri;

  @override
  Future<Uri> discover() async => _hubUri;
}
