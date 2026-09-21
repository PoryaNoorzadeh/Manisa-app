import '../core/persian_digits.dart';

/// Snapshot of one Power Source cluster, including root endpoint zero.
/// No estimate, cached value or missing optional attribute becomes a percentage.
final class PowerSource {
  PowerSource._(this.values);
  final Map<String, Object?> values;
  factory PowerSource.fromMap(Map<Object?, Object?> raw) {
    final values = <String, Object?>{};
    for (final entry in <String, int>{'features': 0xffffffff, 'status': 255,
      'percent': 200, 'chargeLevel': 255, 'chargeState': 255}.entries) {
      if (!raw.containsKey(entry.key)) continue;
      final value = raw[entry.key];
      if (value == null && entry.key == 'percent') {
        values[entry.key] = null;
      } else if (value is int && value >= 0 && value <= entry.value) {
        values[entry.key] = value;
      } else {
        throw const FormatException('invalid power source number');
      }
    }
    for (final key in <String>['replacementNeeded', 'wiredPresent']) {
      if (!raw.containsKey(key)) continue;
      if (raw[key] is! bool) throw const FormatException('invalid power source flag');
      values[key] = raw[key];
    }
    if (!values.containsKey('features') || !values.containsKey('status')) {
      throw const FormatException('missing power source identity');
    }
    return PowerSource._(Map<String, Object?>.unmodifiable(values));
  }
  bool get battery => ((values['features']! as int) & 2) != 0;
  bool get wired => ((values['features']! as int) & 1) != 0;
  String get kind => battery && wired ? 'برق و باتری' : battery ? 'باتری'
      : wired ? 'تغذیهٔ سیمی' : 'منبع تغذیه';
  String get status => switch (values['status']) {
    1 => 'فعال', 2 => 'آماده‌به‌کار', 3 => 'در دسترس نیست', _ => 'نامشخص',
  };
  String get percentage {
    final raw = values['percent'];
    if (raw == null) return 'نامشخص';
    final halfPercent = raw as int;
    final number = (halfPercent / 2).toStringAsFixed(halfPercent.isEven ? 0 : 1);
    return '${toPersianDigits(number).replaceAll('.', '٫')}٪';
  }
  String get chargeLevel => switch (values['chargeLevel']) {
    0 => 'عادی', 1 => 'کم', 2 => 'بحرانی', _ => 'نامشخص',
  };
  String get chargeState => switch (values['chargeState']) {
    1 => 'در حال شارژ', 2 => 'شارژ کامل', 3 => 'در حال شارژ نیست', _ => 'نامشخص',
  };
}
