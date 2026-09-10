class AppConfig {
  const AppConfig({required this.hubUri});

  final Uri hubUri;

  factory AppConfig.fromEnvironment() {
    const raw = String.fromEnvironment(
      'MANISA_HUB_URL',
      defaultValue: 'http://127.0.0.1:8080',
    );
    return AppConfig(hubUri: Uri.parse(raw));
  }
}
