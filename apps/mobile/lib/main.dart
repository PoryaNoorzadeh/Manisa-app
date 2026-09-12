import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/config/app_config.dart';
import 'src/data/manisa_api.dart';
import 'src/discovery/hub_discovery.dart';
import 'src/matter/direct_device_store.dart';
import 'src/matter/direct_matter_app.dart';
import 'src/matter/direct_matter_controller.dart';
import 'src/realtime/manisa_realtime.dart';
import 'src/security/token_store.dart';
import 'src/state/app_controller.dart';

void main() {
  final config = AppConfig.fromEnvironment();

  if (config.mode == ManisaOperatingMode.directMatter) {
    runApp(
      ManisaDirectApp(
        controller: const PlatformDirectMatterController(),
        deviceStore: PreferencesDirectDeviceStore(),
      ),
    );
    return;
  }

  final discovery = MdnsHubDiscovery(fallback: config.hubUri);
  final tokenStore = SecureTokenStore();
  final api = HttpManisaApi(discovery, tokenStore: tokenStore);
  final realtime = ManisaRealtime(discovery, tokenStore: tokenStore);
  final controller = AppController(
    api: api,
    realtime: realtime,
    tokenStore: tokenStore,
  );

  runApp(ManisaApp(controller: controller));
}
