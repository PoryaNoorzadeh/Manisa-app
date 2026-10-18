import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials are never included in device records, logs, QR codes or analytics.
class WifiCredentialStore {
  const WifiCredentialStore({FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;
  final FlutterSecureStorage _storage;
  String _key(String ssid) => 'manisa.wifi.${base64Url.encode(utf8.encode(ssid))}';
  Future<String?> password(String ssid) => _storage.read(key: _key(ssid));
  Future<String?> lastSsid() => _storage.read(key: 'manisa.wifi.last');
  Future<void> remember(String ssid, String password) async {
    await _storage.write(key: _key(ssid), value: password);
    await _storage.write(key: 'manisa.wifi.last', value: ssid);
  }
  Future<void> forget(String ssid) async {
    await _storage.delete(key: _key(ssid));
    if (await lastSsid() == ssid) await _storage.delete(key: 'manisa.wifi.last');
  }
}

const onboardingChannel = MethodChannel('com.manisa/matter/methods');

String onboardingError(Object error) {
  if (error is PlatformException) {
    switch (error.code) {
      case 'permission_denied': return 'دسترسی جست‌وجو داده نشد؛ آن را در تنظیمات گوشی فعال کن.';
      case 'wifi_disabled': return 'وای‌فای و موقعیت گوشی را روشن کن و دوباره جست‌وجو کن.';
      case 'bluetooth_disabled': return 'بلوتوث گوشی را روشن کن.';
      case 'nfc_unavailable': return 'NFC در دسترس نیست؛ آن را روشن کن یا از QR استفاده کن.';
      case 'invalid_nfc': return 'تگ باید حاوی کد اتصال Matter باشد.';
      case 'device_mismatch': return 'کد اتصال متعلق به وسیلهٔ انتخاب‌شده نیست.';
      case 'discovery_cancelled': return 'جست‌وجو لغو شد.';
    }
  }
  return 'عملیات کامل نشد؛ اتصال و دسترسی‌ها را بررسی کن و دوباره تلاش کن.';
}
