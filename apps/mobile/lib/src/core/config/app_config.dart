enum ManisaOperatingMode { directMatter, hub }

class AppConfig {
  const AppConfig({required this.mode, required this.hubUri});

  final ManisaOperatingMode mode;
  final Uri hubUri;

  factory AppConfig.fromEnvironment() {
    const rawMode = String.fromEnvironment(
      'MANISA_MODE',
      defaultValue: 'direct',
    );
    const rawHub = String.fromEnvironment(
      'MANISA_HUB_URL',
      defaultValue: 'http://127.0.0.1:8080',
    );

    final mode = switch (rawMode.trim().toLowerCase()) {
      'direct' || 'direct_matter' => ManisaOperatingMode.directMatter,
      'hub' => ManisaOperatingMode.hub,
      _ => throw ArgumentError.value(
          rawMode,
          'MANISA_MODE',
          'Expected direct or hub',
        ),
    };

    return AppConfig(mode: mode, hubUri: Uri.parse(rawHub));
  }
}
