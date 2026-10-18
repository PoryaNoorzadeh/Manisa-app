import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LocaleStore {
  Future<String?> load();
  Future<void> save(String language);
}

final class EmptyLocaleStore implements LocaleStore {
  const EmptyLocaleStore();
  @override
  Future<String?> load() async => null;
  @override
  Future<void> save(String language) async {}
}

final class PreferencesLocaleStore implements LocaleStore {
  PreferencesLocaleStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  static const key = 'manisa_locale_v1';
  @override
  Future<String?> load() => _preferences.getString(key);
  @override
  Future<void> save(String language) => _preferences.setString(key, language);
}

final class ManisaLocaleController extends ValueNotifier<String> {
  ManisaLocaleController(this.store) : super('fa');
  final LocaleStore store;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _tail = Future.value();
  Future<void> restore() async {
    final revision = _revision;
    try {
      final code = await store.load();
      if (!_disposed && revision == _revision && supported.contains(code))
        value = code!;
    } catch (_) {
      /* First launch remains usable in Persian. */
    }
  }

  static const supported = {'fa', 'en', 'ar'};
  Future<void> select(String code) {
    if (!supported.contains(code)) throw ArgumentError.value(code);
    final revision = ++_revision;
    final task = _tail.then((_) async {
      await store.save(code);
      if (!_disposed && revision == _revision) value = code;
    });
    _tail = task.catchError((Object _) {});
    return task;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ManisaLocaleScope extends InheritedWidget {
  const ManisaLocaleScope({
    required this.controller,
    required super.child,
    super.key,
  });
  final ManisaLocaleController controller;
  static ManisaLocaleController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ManisaLocaleScope>()
      ?.controller;
  @override
  bool updateShouldNotify(ManisaLocaleScope oldWidget) =>
      controller != oldWidget.controller;
}

final class ManisaCopy {
  const ManisaCopy(this.language);
  final String language;
  static ManisaCopy of(BuildContext context) => ManisaCopy(
    ManisaLocaleScope.of(context) == null
        ? 'fa'
        : Localizations.maybeLocaleOf(context)?.languageCode ?? 'fa',
  );
  String number(Object value) {
    var s = value.toString();
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i').replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i');
    }
    s = s.replaceAll('٫', '.').replaceAll('٪', '%');
    if (language == 'en') return s;
    final digits = language == 'fa' ? '۰۱۲۳۴۵۶۷۸۹' : '٠١٢٣٤٥٦٧٨٩';
    return s
        .replaceAllMapped(RegExp('[0-9]'), (m) => digits[int.parse(m[0]!)])
        .replaceAll('.', '٫')
        .replaceAll('%', '٪');
  }

  String text(String source) {
    if (language == 'fa') return source;
    final entry = translations[source];
    if (entry != null) return entry[language == 'en' ? 0 : 1];
    final generated = _generated(source);
    if (generated != null) return generated;
    for (final template in templates) {
      final match = template.$1.firstMatch(source);
      if (match != null)
        return template.$2[language == 'en' ? 0 : 1].replaceAllMapped(
          RegExp(r'\{(\d+)\}'),
          (m) => number(match.group(int.parse(m[1]!))!),
        );
    }
    if (RegExp(r'^[0-9۰-۹٠-٩+%٪°CVAWkWh.٫−—:/ \-]+$').hasMatch(source))
      return number(source);
    // Identifiers, user-assigned names and raw support diagnostics are not translated.
    return source;
  }

  String? _generated(String source) {
    final en = language == 'en';
    final room = RegExp(
      r'^اتاق «(.+)» حذف شود؟(?: ([۰-۹0-9]+) وسیله به بخش «بدون اتاق» منتقل می‌شود\.)?$',
    ).firstMatch(source);
    if (room != null) {
      final count = room.group(2);
      return en
          ? 'Delete room “${room[1]}”?${count == null ? '' : ' ${number(count)} devices will move to No room.'}'
          : 'حذف الغرفة «${room[1]}»؟${count == null ? '' : ' سيتم نقل ${number(count)} أجهزة إلى بلا غرفة.'}';
    }
    final summary = RegExp(
      r'^(آخرین وضعیت: )?([۰-۹0-9]+) از ([۰-۹0-9]+) خروجی روشن(?: · ([۰-۹0-9]+) نامشخص)?$',
    ).firstMatch(source);
    if (summary != null) {
      final prefix = summary[1] == null
          ? ''
          : en
          ? 'Last confirmed: '
          : 'آخر حالة مؤكدة: ';
      final on = number(summary[2]!);
      final total = number(summary[3]!);
      final unknown = summary[4];
      return '$prefix${en ? '$on of $total outputs on' : '$on من $total مخارج تعمل'}${unknown == null
          ? ''
          : en
          ? ' · ${number(unknown)} unknown'
          : ' · ${number(unknown)} غير معروف'}';
    }
    final time = RegExp(r'^([۰-۹0-9]{2}:[۰-۹0-9]{2}) · (.+)$')
        .firstMatch(source);
    if (time != null) {
      final days = time[2]!.split('، ');
      if (days.every((day) => translations.containsKey(day))) {
        return '${number(time[1]!)} · ${days.map(text).join(en ? ', ' : '، ')}';
      }
    }
    final metadata = RegExp(r'^([۰-۹0-9]+) خروجی · (.+)$').firstMatch(source);
    if (metadata != null)
      return '${number(metadata[1]!)} ${en ? 'outputs' : 'مخارج'} · ${metadata[2]}';
    final title = RegExp(r'^اتاق «(.+)»$').firstMatch(source);
    if (title != null)
      return en ? 'Room for “${title[1]}”' : 'غرفة «${title[1]}»';
    final schedule = RegExp(
      r'^زمان‌بندی «(.+)» (اجرا و تأیید شد\.|کامل تأیید نشد؛ وضعیت خروجی‌ها را بررسی کن\.)$',
    ).firstMatch(source);
    if (schedule != null) {
      final confirmed = schedule[2]!.startsWith('اجرا');
      return en
          ? 'Schedule “${schedule[1]}” ${confirmed ? 'ran and was confirmed.' : 'was not fully confirmed. Check the outputs.'}'
          : 'الجدول «${schedule[1]}» ${confirmed ? 'تم تشغيله وتأكيده.' : 'لم يتم تأكيده بالكامل. تحقق من المخارج.'}';
    }
    return null;
  }

  String count(int count, String fa, String en, String ar) =>
      '${number(count)} ${language == 'en'
          ? en
          : language == 'ar'
          ? ar
          : fa}';
  static final templates = <(RegExp, List<String>)>[
    (
      RegExp(r'^مرحلهٔ ([۰-۹0-9]+) از ([۰-۹0-9]+)$'),
      ['Step {1} of {2}', 'الخطوة {1} من {2}'],
    ),
    (
      RegExp(r'^([۰-۹0-9]+) خروجی انتخاب شده$'),
      ['{1} outputs selected', 'تم اختيار {1} مخارج'],
    ),
    (RegExp(r'^سنسور ([۰-۹0-9]+)$'), ['Sensor {1}', 'المستشعر {1}']),
    (RegExp(r'^اندازه‌گیری ([۰-۹0-9]+)$'), ['Measurement {1}', 'القياس {1}']),
    (RegExp(r'^([۰-۹0-9]+) درصد$'), ['{1} percent', '{1} بالمئة']),
    (
      RegExp(r'^([۰-۹0-9]+) وسیله در شبکهٔ خانه در دسترس است\.$'),
      [
        '{1} devices available on your home network.',
        '{1} أجهزة متاحة على شبكة المنزل.',
      ],
    ),
    (RegExp(r'^آخرین بررسی: (.+)$'), ['Last checked: {1}', 'آخر تحقق: {1}']),
    (RegExp(r'^خروجی ([۰-۹0-9]+)$'), ['Output {1}', 'المخرج {1}']),
    (RegExp(r'^([۰-۹0-9]+) خروجی$'), ['{1} outputs', '{1} مخارج']),
    (RegExp(r'^([۰-۹0-9]+) اتاق$'), ['{1} rooms', '{1} غرف']),
    (RegExp(r'^([۰-۹0-9]+) وسیله$'), ['{1} devices', '{1} أجهزة']),
    (
      RegExp(r'^وضعیت ([۰-۹0-9]+) خروجی دریافت نشده$'),
      ['State of {1} outputs not received', 'لم تُستلم حالة {1} مخارج'],
    ),
    (
      RegExp(r'^([۰-۹0-9]+) از ([۰-۹0-9]+) خروجی روشن$'),
      ['{1} of {2} outputs on', '{1} من {2} مخارج تعمل'],
    ),
    (
      RegExp(r'^([۰-۹0-9]+) وسیله در دسترس نیست$'),
      ['{1} devices unavailable', '{1} أجهزة غير متاحة'],
    ),
    (
      RegExp(r'^([۰-۹0-9]+) وسیله در شبکهٔ خانه آماده است\.$'),
      [
        '{1} devices ready on your home network.',
        '{1} أجهزة جاهزة على شبكة المنزل.',
      ],
    ),
  ];
  static const translations = <String, List<String>>{
    'آخرین وضعیت: روشن': ['Last confirmed: On', 'آخر حالة مؤكدة: يعمل'],
    'آخرین وضعیت: خاموش': ['Last confirmed: Off', 'آخر حالة مؤكدة: متوقف'],
    'رنگ انتخاب‌شده': ['Selected color', 'اللون المحدد'],
    'نور': ['Brightness', 'السطوع'],
    "خانه": ["Home", "الرئيسية"],
    "خانهٔ من": ["My home", "بيتي"],
    "کارها": ["Tasks", "المهام"],
    "تنظیمات": ["Settings", "الإعدادات"],
    "افزودن": ["Add", "إضافة"],
    "افزودن به خانه": ["Add to your home", "إضافة إلى المنزل"],
    "افزودن دستگاه": ["Add device", "إضافة جهاز"],
    "افزودن وسیله": ["Add device", "إضافة جهاز"],
    "افزودن اتاق": ["Add room", "إضافة غرفة"],
    "اتاق‌ها": ["Rooms", "الغرف"],
    "همهٔ اتاق‌ها": ["All rooms", "كل الغرف"],
    "بدون اتاق": ["No room", "بلا غرفة"],
    "نام خانه": ["Home name", "اسم المنزل"],
    "نام اتاق": ["Room name", "اسم الغرفة"],
    "نام وسیله": ["Device name", "اسم الجهاز"],
    "نام خروجی": ["Output name", "اسم المخرج"],
    "نام خروجی‌ها": ["Output names", "أسماء المخارج"],
    "ذخیره": ["Save", "حفظ"],
    "انصراف": ["Cancel", "إلغاء"],
    "بستن": ["Close", "إغلاق"],
    "بازگشت": ["Back", "رجوع"],
    "ادامه": ["Continue", "متابعة"],
    "ویرایش": ["Edit", "تعديل"],
    "حذف": ["Delete", "حذف"],
    "بررسی": ["Check", "تحقق"],
    "تلاش دوباره": ["Try again", "إعادة المحاولة"],
    "بررسی وضعیت": ["Refresh", "تحديث الحالة"],
    "تنظیمات وسیله": ["Device settings", "إعدادات الجهاز"],
    "تنظیمات اتاق": ["Room settings", "إعدادات الغرفة"],
    "تغییر نام اتاق": ["Rename room", "تغيير اسم الغرفة"],
    "تغییر نام وسیله": ["Rename device", "تغيير اسم الجهاز"],
    "تغییر نام خروجی": ["Rename output", "تغيير اسم المخرج"],
    "تغییر اتاق": ["Move to room", "نقل إلى غرفة"],
    "انتقال به بالا": ["Move up", "نقل إلى الأعلى"],
    "انتقال به پایین": ["Move down", "نقل إلى الأسفل"],
    "حذف اتاق": ["Delete room", "حذف الغرفة"],
    "حذف اتاق؟": ["Delete room?", "حذف الغرفة؟"],
    "حذف وسیله": ["Remove device", "إزالة الجهاز"],
    "اشتراک‌گذاری": ["Share", "مشاركة"],
    "علاقه‌مندی‌ها": ["Favorites", "المفضلة"],
    "حذف از علاقه‌مندی‌ها": ["Remove from favorites", "إزالة من المفضلة"],
    "افزودن به علاقه‌مندی‌ها": ["Add to favorites", "إضافة إلى المفضلة"],
    "کنترل وسیله": ["Device controls", "التحكم بالجهاز"],
    "روشن": ["On", "يعمل"],
    "خاموش": ["Off", "متوقف"],
    "در دسترس نیست": ["Unavailable", "غير متاح"],
    "دریافت نشده": ["Not received", "لم تُستلم"],
    "وضعیت دریافت نشده": ["State not received", "لم تُستلم الحالة"],
    "در حال دریافت وضعیت": ["Reading state", "قراءة الحالة"],
    "در حال انجام…": ["Working…", "جارٍ التنفيذ…"],
    "در حال تازه‌سازی": ["Refreshing", "جارٍ التحديث"],
    "در حال آماده‌سازی ارتباط…": [
      "Preparing connection…",
      "جارٍ إعداد الاتصال…",
    ],
    "در حال تازه‌سازی؛ کنترل‌های آماده قابل استفاده‌اند.": [
      "Refreshing. Ready controls remain available.",
      "جارٍ التحديث. تظل عناصر التحكم الجاهزة متاحة.",
    ],
    "نیاز به به‌روزرسانی": ["Refresh needed", "يلزم التحديث"],
    "آخرین مقدار؛ نیاز به به‌روزرسانی": [
      "Last reading; refresh needed",
      "آخر قراءة؛ يلزم التحديث",
    ],
    "دما": ["Temperature", "درجة الحرارة"],
    "رطوبت": ["Humidity", "الرطوبة"],
    "تشخیص حضور": ["Presence", "الحضور"],
    "در / پنجره": ["Door / window", "باب / نافذة"],
    "حضور تشخیص داده شد": ["Presence detected", "تم رصد حضور"],
    "حضوری تشخیص داده نشده": ["No presence detected", "لم يُرصد حضور"],
    "بسته": ["Closed", "مغلق"],
    "باز": ["Open", "مفتوح"],
    "دریافت دوباره": ["Refresh reading", "تحديث القراءة"],
    "برق وصل است": ["Power on", "التيار موصول"],
    "برق قطع است": ["Power off", "التيار مفصول"],
    "زبان برنامه": ["App language", "لغة التطبيق"],
    "پیش‌فرض": ["Default", "الافتراضية"],
    "خانه و مانیسا": ["Your home", "منزلك"],
    "تنظیمات کم‌استفاده اینجا می‌مانند تا صفحهٔ کنترل ساده بماند.": [
      "Manage your home and preferences.",
      "إدارة منزلك وتفضيلاتك.",
    ],
    "وسایل ثبت‌شده": ["Saved devices", "الأجهزة المحفوظة"],
    "اتصال محلی": ["Local connection", "اتصال محلي"],
    "کنترل داخل خانه از شبکهٔ خانه استفاده می‌کند؛ اینترنت و شبکهٔ خانه یکسان نیستند.":
        [
          "Devices are controlled over your home network. Internet access is separate.",
          "يتم التحكم بالأجهزة عبر شبكة المنزل. الاتصال بالإنترنت منفصل.",
        ],
    "راهنما و پشتیبانی": ["Help and support", "المساعدة والدعم"],
    "جزئیات فنی فقط هنگام نیاز به پشتیبانی نمایش داده می‌شود.": [
      "Connection details are available when you need help.",
      "تتوفر تفاصيل الاتصال عند الحاجة إلى المساعدة.",
    ],
    "مثلاً خانهٔ ما": ["For example, Our home", "مثلاً، منزلنا"],
    "مثلاً پذیرایی یا اتاق خواب": [
      "For example, Living room or Bedroom",
      "مثلاً، المعيشة أو غرفة النوم",
    ],
    "مثلاً کلید پذیرایی": [
      "For example, Living room switch",
      "مثلاً، مفتاح المعيشة",
    ],
    "تغییرات ذخیره نشد. دوباره تلاش کن.": [
      "Changes were not saved. Try again.",
      "لم تُحفظ التغييرات. حاول مجددًا.",
    ],
    "نام خانه را وارد کن.": ["Enter a home name.", "أدخل اسم المنزل."],
    "نام اتاق را وارد کن.": ["Enter a room name.", "أدخل اسم الغرفة."],
    "اتاقی با این نام وجود دارد.": [
      "A room with this name already exists.",
      "توجد غرفة بهذا الاسم.",
    ],
    "سناریوها": ["Scenes", "المشاهد"],
    "سناریو": ["Scene", "مشهد"],
    "سناریوی جدید": ["New scene", "مشهد جديد"],
    "زمان‌بندی‌ها": ["Schedules", "الجداول"],
    "زمان‌بندی جدید": ["New schedule", "جدول جديد"],
    "نام سناریو": ["Scene name", "اسم المشهد"],
    "اجرا": ["Run", "تشغيل"],
    "یک لمس، چند تغییر": [
      "One tap, several changes",
      "لمسة واحدة، عدة تغييرات",
    ],
    "خانه با سبک زندگی تو هماهنگ می‌شود": [
      "Your home, in your rhythm",
      "منزلك على إيقاعك",
    ],
    "چند وسیله را با یک لمس کنترل کن یا زمان اجرای آن را مشخص کن.": [
      "Control several devices with one tap, or set a schedule.",
      "تحكم بعدة أجهزة بلمسة أو حدد جدولًا لتشغيلها.",
    ],
    "دیدن سناریوها": ["View scenes", "عرض المشاهد"],
    "دیدن زمان‌بندی‌ها": ["View schedules", "عرض الجداول"],
    "حالت دلخواه چند وسیله را ذخیره و با یک لمس اجرا کن.": [
      "Save the settings you like and run them with one tap.",
      "احفظ الإعدادات التي تفضلها وشغّلها بلمسة.",
    ],
    "یک سناریو را در روزها و ساعت مشخص روی همین گوشی اجرا کن.": [
      "Run a scene at selected times on this phone.",
      "شغّل مشهدًا في أوقات محددة على هذا الهاتف.",
    ],
    "زمان‌بندی‌های فعلی روی همین گوشی اجرا می‌شوند. فرمان ناموفق خودکار تکرار نمی‌شود.":
        [
          "Schedules run on this phone while the app is active. Failed commands are not retried automatically.",
          "تعمل الجداول على هذا الهاتف أثناء نشاط التطبيق. لا تُكرر الأوامر الفاشلة تلقائيًا.",
        ],
    "روال‌های قابل پیش‌بینی": ["Your daily routines", "روتينك اليومي"],
    "برای سناریوهای آماده، روز و ساعت اجرا را مشخص کن.": [
      "Choose days and a time for a saved scene.",
      "اختر أيامًا ووقتًا لمشهد محفوظ.",
    ],
    "هنوز سناریویی نساخته‌ای.": ["No scenes yet.", "لا توجد مشاهد بعد."],
    "هنوز زمان‌بندی‌ای نساخته‌ای.": ["No schedules yet.", "لا توجد جداول بعد."],
    "ابتدا یک سناریو بساز، سپس برای آن زمان تعیین کن.": [
      "Create a scene first, then choose when it runs.",
      "أنشئ مشهدًا أولًا، ثم حدد وقت تشغيله.",
    ],
    "برای نمونه، چراغ‌های موردنیاز مطالعه را در یک سناریو ذخیره کن.": [
      "For example, save your reading lights as a scene.",
      "مثلاً، احفظ إضاءة القراءة كمشهد.",
    ],
    "وضعیت خروجی‌ها، شدت نور و رنگ را ذخیره کن و نتیجهٔ واقعی هرکدام را ببین.": [
      "Save output states, brightness and color, then see confirmed results.",
      "احفظ حالات المخارج والسطوع واللون، ثم شاهد النتائج المؤكدة.",
    ],
    "خروجی‌هایی را انتخاب کن که با این سناریو تغییر می‌کنند.": [
      "Choose the outputs this scene controls.",
      "اختر المخارج التي يتحكم بها هذا المشهد.",
    ],
    "تغییر خروجی‌ها": ["Change outputs", "تغيير المخارج"],
    "هنوز خروجی قابل‌کنترلی اضافه نشده است.": [
      "No controllable outputs yet.",
      "لا توجد مخارج قابلة للتحكم بعد.",
    ],
    "حذف خروجی از سناریو": [
      "Remove output from scene",
      "إزالة المخرج من المشهد",
    ],
    "خروجی حذف‌شده یا در دسترس نیست": [
      "Output removed or unavailable",
      "المخرج محذوف أو غير متاح",
    ],
    "تنظیم شدت نور": ["Set brightness", "تعيين السطوع"],
    "تنظیم رنگ": ["Set color", "تعيين اللون"],
    "این تنظیمات فقط هنگام اجرای سناریو اعمال می‌شوند.": [
      "These settings apply only when the scene runs.",
      "تُطبق هذه الإعدادات عند تشغيل المشهد فقط.",
    ],
    "اگر خاموش باشد، شدت نور تغییر نمی‌کند.": [
      "Brightness is unchanged when the output is off.",
      "لا يتغير السطوع عندما يكون المخرج متوقفًا.",
    ],
    "رنگ دلخواه سناریو؛ فقط هنگام اجرا اعمال می‌شود.": [
      "Scene color; applied only when it runs.",
      "لون المشهد؛ يُطبق عند التشغيل فقط.",
    ],
    "قابلیت نور تغییر کرده؛ حذف تنظیمات نور از این خروجی": [
      "Lighting capability changed; remove these lighting settings",
      "تغيرت إمكانات الإضاءة؛ أزل إعدادات الإضاءة هذه",
    ],
    "تغییرات ذخیره نشده‌اند": ["Unsaved changes", "تغييرات غير محفوظة"],
    "می‌خواهی بدون ذخیرهٔ این تغییرات خارج شوی؟": [
      "Leave without saving these changes?",
      "الخروج دون حفظ هذه التغييرات؟",
    ],
    "ادامهٔ ویرایش": ["Keep editing", "متابعة التعديل"],
    "خروج بدون ذخیره": ["Discard changes", "تجاهل التغييرات"],
    "حذف سناریو؟": ["Delete scene?", "حذف المشهد؟"],
    "حذف سناریو ذخیره نشد. دوباره تلاش کن.": [
      "Scene deletion was not saved. Try again.",
      "لم يُحفظ حذف المشهد. حاول مجددًا.",
    ],
    "زمان‌بندی ذخیره نشد. دوباره تلاش کن.": [
      "Schedule was not saved. Try again.",
      "لم يُحفظ الجدول. حاول مجددًا.",
    ],
    "زمان‌بندی روی همین گوشی اجرا می‌شود. اجرای عقب‌افتاده فقط تا ۱۰ دقیقه جبران می‌شود و فرمان دوبار پخش نمی‌شود.":
        [
          "Schedules run on this phone. Missed runs can be recovered for up to 10 minutes; commands are not duplicated.",
          "تعمل الجداول على هذا الهاتف. يمكن تعويض التشغيل الفائت خلال 10 دقائق؛ لا تُكرر الأوامر.",
        ],
    "در حال اجرا؛ نتیجهٔ هر خروجی بررسی می‌شود…": [
      "Running and checking each output…",
      "جارٍ التشغيل والتحقق من كل مخرج…",
    ],
    "توقف ادامهٔ اجرا": ["Stop remaining actions", "إيقاف الإجراءات المتبقية"],
    "تلاش مجدد موارد تأییدنشده": [
      "Retry unconfirmed actions",
      "إعادة المحاولة للإجراءات غير المؤكدة",
    ],
    "برای نتیجهٔ نامشخص، ممکن است فرمان اجرا شده باشد. تلاش مجدد همان تنظیمات ذخیره‌شده را درخواست می‌کند.":
        [
          "An unconfirmed command may have run. Retrying requests the same saved settings.",
          "قد يكون الأمر غير المؤكد قد نُفذ. إعادة المحاولة تطلب الإعدادات المحفوظة نفسها.",
        ],
    "نور پس‌زمینهٔ کلیدها": ["Switch backlights", "إضاءة المفاتيح الخلفية"],
    "رنگ خانه": ["Home color", "لون المنزل"],
    "رنگ این اتاق": ["Room color", "لون الغرفة"],
    "استفاده از رنگ خانه": ["Use home color", "استخدام لون المنزل"],
    "رنگ جداگانه": ["Custom color", "لون مخصص"],
    "اعمال رنگ": ["Apply color", "تطبيق اللون"],
    "انتخاب کلیدها": ["Choose switches", "اختيار المفاتيح"],
    "خروجی‌های نور پس‌زمینه را مشخص کن.": [
      "Select the outputs that control switch backlights.",
      "حدد المخارج التي تتحكم بإضاءة المفاتيح الخلفية.",
    ],
    "هیچ کلیدی انتخاب نشده است.": [
      "No switches selected.",
      "لم يتم اختيار مفاتيح.",
    ],
    "رنگ ذخیره نشده است.": ["No color saved.", "لم يُحفظ لون."],
    "رنگ فقط با لمس «اعمال رنگ» به کلیدها ارسال می‌شود.": [
      "Color is sent only when you tap Apply color.",
      "يُرسل اللون فقط عند الضغط على تطبيق اللون.",
    ],
    "اعمال رنگ در حال انجام است…": ["Applying color…", "جارٍ تطبيق اللون…"],
    "ذخیرهٔ تنظیمات انجام نشد. دوباره تلاش کن.": [
      "Settings could not be saved. Try again.",
      "تعذر حفظ الإعدادات. حاول مجددًا.",
    ],
    "خواندن تنظیمات انجام نشد. دوباره تلاش کن.": [
      "Settings could not be loaded. Try again.",
      "تعذر تحميل الإعدادات. حاول مجددًا.",
    ],
    "شدت نور": ["Brightness", "السطوع"],
    "شدت نور دریافت نشده": ["Brightness not received", "لم يُستلم السطوع"],
    "رنگ نور": ["Light color", "لون الإضاءة"],
    "رنگ فعلی دریافت نشده": [
      "Current color not received",
      "لم يُستلم اللون الحالي",
    ],
    "رنگ نیاز به به‌روزرسانی دارد": [
      "Color needs refreshing",
      "يلزم تحديث اللون",
    ],
    "دریافت رنگ": ["Refresh color", "تحديث اللون"],
    "سفید": ["White", "أبيض"],
    "قرمز": ["Red", "أحمر"],
    "نارنجی": ["Orange", "برتقالي"],
    "زرد": ["Yellow", "أصفر"],
    "سبز": ["Green", "أخضر"],
    "آبی": ["Blue", "أزرق"],
    "بنفش": ["Purple", "بنفسجي"],
    "افزودن کلید، چراغ یا سنسور": [
      "Add a switch, light or sensor",
      "إضافة مفتاح أو مصباح أو مستشعر",
    ],
    "مرتب‌کردن دستگاه‌ها بر اساس اتاق": [
      "Organize devices by room",
      "تنظيم الأجهزة حسب الغرفة",
    ],
    "اولین وسیله را اضافه کن": ["Add your first device", "أضف جهازك الأول"],
    "هنوز وسیله‌ای در این اتاق نیست": [
      "No devices in this room yet",
      "لا توجد أجهزة في هذه الغرفة بعد",
    ],
    "در حال خواندن خانهٔ تو…": ["Loading your home…", "جارٍ تحميل منزلك…"],
    "دریافت کنترل‌های وسیله": [
      "Loading device controls",
      "تحميل عناصر التحكم بالجهاز",
    ],
    "کد اتصال": ["Setup code", "رمز الإعداد"],
    "آماده‌کردن وسیله": ["Prepare device", "تجهيز الجهاز"],
    "وای‌فای خانه": ["Home Wi-Fi", "شبكة واي فاي المنزل"],
    "اسکن کد وسیله": ["Scan device code", "مسح رمز الجهاز"],
    "کد QR روی وسیله یا جعبه را اسکن کن. برای این کار اجازهٔ دوربین لازم است.":
        [
          "Scan the QR code on the device or box. Camera permission is needed.",
          "امسح رمز QR الموجود على الجهاز أو العلبة. يلزم إذن الكاميرا.",
        ],
    "خواندن تگ NFC": ["Read NFC tag", "قراءة علامة NFC"],
    "واردکردن کد": ["Enter setup code", "إدخال رمز الإعداد"],
    "متن کد QR": ["QR code text", "نص رمز QR"],
    "اگر متن QR را داری، اینجا وارد کن.": [
      "Paste the QR code text here.",
      "ألصق نص رمز QR هنا.",
    ],
    "وسیلهٔ اشتراکی": ["Shared device", "جهاز مشترك"],
    "اسکن QR موقت از گوشی صاحب وسیله؛ بدون ورود رمز وای‌فای": [
      "Scan a temporary QR from the owner's phone; no Wi-Fi password needed.",
      "امسح رمز QR مؤقتًا من هاتف المالك؛ لا حاجة لكلمة مرور واي فاي.",
    ],
    "وسیله روشن باشد و گوشی نزدیک آن بماند.": [
      "Keep the device powered on and your phone nearby.",
      "أبقِ الجهاز قيد التشغيل والهاتف قريبًا منه.",
    ],
    "به همان شبکهٔ وسیله وصل باش؛ کد اشتراک‌گذاری باید هنوز معتبر باشد. نیازی به بازنشانی وسیله نیست.":
        [
          "Join the device's network and use a valid sharing code. No device reset is needed.",
          "اتصل بشبكة الجهاز واستخدم رمز مشاركة صالحًا. لا حاجة لإعادة ضبط الجهاز.",
        ],
    "طبق راهنمای وسیله، آن را در حالت اتصال قرار بده. بازنشانی کارخانه با حالت اتصال فرق دارد.":
        [
          "Put the device in pairing mode using its guide. Pairing mode is different from a factory reset.",
          "ضع الجهاز في وضع الاقتران وفق دليله. يختلف وضع الاقتران عن إعادة ضبط المصنع.",
        ],
    "بلوتوث و وای‌فای را روشن کن. هنگام درخواست دسترسی به دستگاه‌های نزدیک، اجازه بده؛ در نسخه‌های قدیمی Android ممکن است اجازهٔ موقعیت لازم باشد.":
        [
          "Turn on Bluetooth and Wi-Fi. Allow nearby-device access when asked. Older Android versions may require location permission.",
          "شغّل البلوتوث وواي فاي. اسمح بالوصول إلى الأجهزة القريبة عند الطلب. قد تتطلب إصدارات أندرويد الأقدم إذن الموقع.",
        ],
    "شبکهٔ خانه را انتخاب کن. برای بیشتر وسایل، شبکهٔ ۲٫۴ گیگاهرتز مناسب است.": [
      "Choose your home network. Most devices use 2.4 GHz Wi-Fi.",
      "اختر شبكة منزلك. تستخدم معظم الأجهزة شبكة واي فاي بتردد 2.4 غيغاهرتز.",
    ],
    "استفاده از وای‌فای متصل گوشی": [
      "Use phone's current Wi-Fi",
      "استخدام شبكة واي فاي الهاتف الحالية",
    ],
    "نمایش شبکه‌های وای‌فای": ["Show Wi-Fi networks", "عرض شبكات واي فاي"],
    "انتخاب وای‌فای": ["Choose Wi-Fi", "اختيار شبكة واي فاي"],
    "نام وای‌فای": ["Wi-Fi name", "اسم شبكة واي فاي"],
    "رمز وای‌فای": ["Wi-Fi password", "كلمة مرور واي فاي"],
    "نمایش رمز": ["Show password", "إظهار كلمة المرور"],
    "پنهان‌کردن رمز": ["Hide password", "إخفاء كلمة المرور"],
    "رمز روی این گوشی به‌خاطر سپرده شود": [
      "Remember password on this phone",
      "حفظ كلمة المرور على هذا الهاتف",
    ],
    "پاک‌کردن رمز ذخیره‌شدهٔ این شبکه": [
      "Forget this network's saved password",
      "نسيان كلمة مرور هذه الشبكة المحفوظة",
    ],
    "رمز ذخیره‌شده پاک شد.": [
      "Saved password removed.",
      "أُزيلت كلمة المرور المحفوظة.",
    ],
    "حذف رمز انجام نشد؛ دوباره تلاش کن.": [
      "Password could not be removed. Try again.",
      "تعذرت إزالة كلمة المرور. حاول مجددًا.",
    ],
    "وسیله اضافه شد؛ ذخیرهٔ امن رمز انجام نشد.": [
      "Device added; the password could not be stored securely.",
      "أُضيف الجهاز؛ تعذر حفظ كلمة المرور بأمان.",
    ],
    "لغو جست‌وجو": ["Cancel search", "إلغاء البحث"],
    "اتصال وسیله": ["Connect device", "توصيل الجهاز"],
    "در حال اتصال…": ["Connecting…", "جارٍ الاتصال…"],
    "در حال اتصال وسیله… نزدیک آن بمان.": [
      "Connecting device… Stay nearby.",
      "جارٍ توصيل الجهاز… ابقَ قريبًا.",
    ],
    "در حال ذخیرهٔ وسیله…": ["Saving device…", "جارٍ حفظ الجهاز…"],
    "در حال ذخیره…": ["Saving…", "جارٍ الحفظ…"],
    "ذخیرهٔ دوباره": ["Retry saving", "إعادة محاولة الحفظ"],
    "وسیله اضافه شد": ["Device added", "تمت إضافة الجهاز"],
    "اتصال کامل نشد": ["Connection incomplete", "لم يكتمل الاتصال"],
    "وسیله متصل شد؛ ذخیره کامل نشد": [
      "Device connected; saving incomplete",
      "تم توصيل الجهاز؛ لم يكتمل الحفظ",
    ],
    "کد دریافت شد": ["Code received", "تم استلام الرمز"],
    "کد روی وسیله را اسکن کن": [
      "Scan the code on your device",
      "امسح الرمز الموجود على الجهاز",
    ],
    "کد QR معتبر Matter را اسکن یا متن آن را وارد کن.": [
      "Scan a valid Matter QR code or enter its text.",
      "امسح رمز QR صالحًا لـ Matter أو أدخل نصه.",
    ],
    "نام وسیله، کد اتصال و نام وای‌فای را بررسی کن.": [
      "Check the device name, setup code and Wi-Fi name.",
      "تحقق من اسم الجهاز ورمز الإعداد واسم شبكة واي فاي.",
    ],
    "کد QR روی وسیله را داخل کادر قرار بده.": [
      "Place the device QR code inside the frame.",
      "ضع رمز QR الخاص بالجهاز داخل الإطار.",
    ],
    "کد روی وسیله را اسکن کن؛ مرحله‌به‌مرحله برای اتصال راهنمایی‌ات می‌کنیم.": [
      "Scan your device code. We'll guide you through connecting it.",
      "امسح رمز جهازك. سنرشدك خطوة بخطوة لتوصيله.",
    ],
    "اشتراک‌گذاری وسیله": ["Share device", "مشاركة الجهاز"],
    "فقط به فرد مورد اعتماد نشان بده؛ گوشی دوم دسترسی مستقل کنترل این وسیله را می‌گیرد.":
        [
          "Show this only to someone you trust. Their phone gets independent control of this device.",
          "اعرض هذا فقط لشخص تثق به. سيحصل هاتفه على تحكم مستقل بالجهاز.",
        ],
    "هر دو گوشی را به شبکهٔ خانه وصل کن. در گوشی دوم «افزودن وسیله» و سپس «وسیلهٔ اشتراکی» را انتخاب و این QR را اسکن کن.":
        [
          "Connect both phones to the home network. On the second phone, choose Add device, then Shared device, and scan this QR.",
          "صل الهاتفين بشبكة المنزل. على الهاتف الثاني اختر إضافة جهاز، ثم جهاز مشترك، وامسح رمز QR هذا.",
        ],
    "بستن صفحه دسترسی فرد اضافه‌شده را لغو نمی‌کند. کد حداکثر ۳ دقیقه معتبر است؛ مدیریت و حذف دسترسی از گوشی دوم انجام می‌شود.":
        [
          "Closing this page does not revoke access. The code lasts up to 3 minutes. Manage or remove access on the second phone.",
          "إغلاق الصفحة لا يلغي الوصول. الرمز صالح لمدة تصل إلى 3 دقائق. تُدار صلاحية الوصول أو تُزال من الهاتف الثاني.",
        ],
    "حذف روی وسیله تأیید نشد.": [
      "Removal was not confirmed by the device.",
      "لم يؤكد الجهاز الإزالة.",
    ],
    "جزئیات برای پشتیبانی": ["Support details", "تفاصيل الدعم"],
    "راهنمای اتصال": ["Connection help", "مساعدة الاتصال"],
    "هر نام به خروجی واقعی دستگاه متصل می‌ماند. برای شناسایی، خودت می‌توانی خروجی را امتحان کنی.":
        [
          "Names stay linked to their actual outputs. Test an output yourself to identify it.",
          "تظل الأسماء مرتبطة بمخارجها الفعلية. يمكنك اختبار المخرج بنفسك للتعرف عليه.",
        ],
    "رنگ خانه · قابل تغییر برای هر اتاق": [
      "Home color · Customize each room",
      "لون المنزل · تخصيص لكل غرفة",
    ],
    "اطلاعات تازهٔ تغذیه دریافت نشد؛ دوباره تلاش کن.": [
      "Fresh power information was not received. Try again.",
      "لم تُستلم معلومات طاقة حديثة. حاول مجددًا.",
    ],
    "این وسیله حذف شده است.": [
      "This device has been removed.",
      "تمت إزالة هذا الجهاز.",
    ],
    "باتری نیاز به تعویض دارد": [
      "Battery needs replacing",
      "يلزم استبدال البطارية",
    ],
    "باتری و تغذیه": ["Battery and power", "البطارية والطاقة"],
    "بازگشت به خانه": ["Back to home", "العودة إلى الرئيسية"],
    "بررسی ارتباط": ["Check connection", "التحقق من الاتصال"],
    "در حال دریافت اطلاعات تغذیه…": [
      "Reading power information…",
      "جارٍ قراءة معلومات الطاقة…",
    ],
    "مقادیر مربوط به آخرین دریافت هستند.": [
      "Showing the last received readings.",
      "تُعرض آخر قراءات مستلمة.",
    ],
    "خانه خوانده نشد. دوباره تلاش کن.": [
      "Your home could not be loaded. Try again.",
      "تعذر تحميل منزلك. حاول مجددًا.",
    ],
    "وسیله پیدا نشد. نزدیک آن بمان و حالت اتصال و بلوتوث را بررسی کن.": [
      "Device not found. Stay nearby and check pairing mode and Bluetooth.",
      "لم يُعثر على الجهاز. ابقَ قريبًا وتحقق من وضع الاقتران والبلوتوث.",
    ],
    "حذف تأیید نشد. وسیله در فهرست باقی مانده؛ اتصال آن را بررسی کن و دوباره تلاش کن.":
        [
          "Removal was not confirmed. The device remains listed. Check its connection and try again.",
          "لم تتأكد الإزالة. يظل الجهاز في القائمة. تحقق من اتصاله وحاول مجددًا.",
        ],
    "تغییر وضعیت تأیید نشد. وضعیت وسیله را دوباره بررسی کن.": [
      "The state change was not confirmed. Refresh the device state.",
      "لم يتأكد تغيير الحالة. حدّث حالة الجهاز.",
    ],
    "دادهٔ تازهٔ سنسور دریافت نشد. اتصال وسیله را بررسی کن و دوباره تلاش کن.": [
      "No fresh sensor reading. Check the device connection and try again.",
      "لم تُستلم قراءة حديثة للمستشعر. تحقق من اتصال الجهاز وحاول مجددًا.",
    ],
    "رنگ تأیید نشد. برای دریافت رنگ واقعی، وضعیت را دوباره بررسی کن.": [
      "Color was not confirmed. Refresh to get the device's actual color.",
      "لم يتأكد اللون. حدّث الحالة للحصول على لون الجهاز الفعلي.",
    ],
    "تغییر شدت نور تأیید نشد. وضعیت وسیله را دوباره بررسی کن.": [
      "Brightness change was not confirmed. Refresh the device state.",
      "لم يتأكد تغيير السطوع. حدّث حالة الجهاز.",
    ],
    "کنترل‌های تازه پیدا شدند، اما ذخیره نشدند. دوباره وضعیت را بررسی کن.": [
      "New controls were found but not saved. Refresh again.",
      "عُثر على عناصر تحكم جديدة لكن لم تُحفظ. حدّث مجددًا.",
    ],
    "وضعیت تازه دریافت نشد. برق وسیله و اتصال به وای‌فای خانه را بررسی کن.": [
      "No fresh state received. Check device power and home Wi-Fi.",
      "لم تُستلم حالة حديثة. تحقق من طاقة الجهاز وشبكة المنزل.",
    ],
    "ارتباط مانیسا راه‌اندازی نشد. دسترسی‌ها را بررسی کن و دوباره تلاش کن.": [
      "Manisa could not start the connection. Check permissions and try again.",
      "تعذر على مانیسا بدء الاتصال. تحقق من الأذونات وحاول مجددًا.",
    ],
    "این مرحله کامل نشد. اتصال و دسترسی‌ها را بررسی کن و دوباره تلاش کن.": [
      "This step did not finish. Check the connection and permissions, then try again.",
      "لم تكتمل هذه الخطوة. تحقق من الاتصال والأذونات ثم حاول مجددًا.",
    ],
    "یک نام برای اتاق بنویس.": ["Enter a room name.", "أدخل اسمًا للغرفة."],
    "یک نام برای خانه بنویس.": ["Enter a home name.", "أدخل اسمًا للمنزل."],
    "نام ذخیره نشد. دوباره تلاش کن.": [
      "Name was not saved. Try again.",
      "لم يُحفظ الاسم. حاول مجددًا.",
    ],
    "برای همهٔ خروجی‌ها نام بنویس.": [
      "Name every output.",
      "أدخل اسمًا لكل مخرج.",
    ],
    "نام خروجی‌ها ذخیره نشد. دوباره تلاش کن.": [
      "Output names were not saved. Try again.",
      "لم تُحفظ أسماء المخارج. حاول مجددًا.",
    ],
    "رمز ذخیره‌شده خوانده نشد؛ رمز را وارد کن.": [
      "Saved password could not be read. Enter it manually.",
      "تعذرت قراءة كلمة المرور المحفوظة. أدخلها يدويًا.",
    ],
    "در حال دریافت وای‌فای متصل گوشی…": [
      "Reading the phone's connected Wi-Fi…",
      "جارٍ قراءة شبكة واي فاي الهاتف…",
    ],
    "وای‌فای متصل انتخاب شد؛ رمز را فقط بار اول وارد کن.": [
      "Connected Wi-Fi selected. Enter its password the first time.",
      "تم اختيار شبكة واي فاي المتصلة. أدخل كلمة مرورها في المرة الأولى.",
    ],
    "وای‌فای متصل و رمز ذخیره‌شده آماده‌اند.": [
      "Connected Wi-Fi and saved password are ready.",
      "شبكة واي فاي المتصلة وكلمة المرور المحفوظة جاهزتان.",
    ],
    "وای‌فای متصل قابل دریافت نیست؛ شبکه را انتخاب یا نامش را وارد کن.": [
      "Current Wi-Fi could not be read. Choose a network or enter its name.",
      "تعذرت قراءة شبكة واي فاي الحالية. اختر شبكة أو أدخل اسمها.",
    ],
    "کنترل تک‌خروجی": ["Single-output control", "تحكم بمخرج واحد"],
    "در انتظار شناسایی قابلیت‌ها": [
      "Discovering capabilities",
      "جارٍ اكتشاف الإمكانات",
    ],
    "سنسور حضور": ["Presence sensor", "مستشعر حضور"],
    "سنسور در و پنجره": ["Door and window sensor", "مستشعر باب ونافذة"],
    "سنسور چندمنظوره": ["Multi-purpose sensor", "مستشعر متعدد الأغراض"],
    "سنسور محیطی": ["Climate sensor", "مستشعر المناخ"],
    "پریز هوشمند": ["Smart socket", "مقبس ذكي"],
    "وسیلهٔ ترکیبی": ["Combined device", "جهاز متعدد الوظائف"],
    "اندازه‌گیری‌ها و کنترل‌ها در صفحهٔ وسیله": [
      "Readings and controls in device details",
      "القراءات والتحكم في تفاصيل الجهاز",
    ],
    "ساخت اتاق": ["Create room", "إنشاء غرفة"],
    "همه‌چیز آماده است": ["Everything is ready", "كل شيء جاهز"],
    "خانه برای اولین وسیله آماده است": [
      "Ready for your first device",
      "جاهز لجهازك الأول",
    ],
    "در حال دریافت وضعیت خانه": [
      "Reading home state",
      "جارٍ قراءة حالة المنزل",
    ],
    "ارتباط خانه آماده نیست": [
      "Home connection is not ready",
      "اتصال المنزل غير جاهز",
    ],
    "در حال بازیابی ارتباط": ["Reconnecting", "جارٍ إعادة الاتصال"],
    "کنترل‌های آماده همچنان قابل استفاده‌اند.": [
      "Ready controls remain available.",
      "تظل عناصر التحكم الجاهزة متاحة.",
    ],
    "راه‌اندازی ارتباط را دوباره امتحان کن.": [
      "Try starting the connection again.",
      "حاول بدء الاتصال مجددًا.",
    ],
    "وسیله را اضافه کن و اولین کنترل را همین‌جا ببین.": [
      "Add a device and control it here.",
      "أضف جهازًا وتحكم به هنا.",
    ],
    "آخرین شبکه‌های دیده‌شده؛ اسکن تازه فعلاً در دسترس نیست.": [
      "Last seen networks. A fresh scan is not available right now.",
      "آخر الشبكات المرصودة. لا يتوفر مسح جديد حاليًا.",
    ],
    "آخرین وضعیت معتبر حفظ شده و مانیسا دوباره تلاش می‌کند.": [
      "Your last confirmed state is kept while Manisa reconnects.",
      "تُحفظ آخر حالة مؤكدة أثناء إعادة الاتصال.",
    ],
    "آماده‌سازی": ["Preparation", "التجهيز"],
    "اتاق جدید": ["New room", "غرفة جديدة"],
    "ارتباط آماده نیست": ["Connection not ready", "الاتصال غير جاهز"],
    "ارتباط قطع است؛ وضعیت تازه دریافت نشده.": [
      "Disconnected. No fresh state received.",
      "الاتصال مقطوع. لم تُستلم حالة حديثة.",
    ],
    "امتحان این خروجی": ["Test this output", "اختبار هذا المخرج"],
    "انتخاب رنگ از طیف": ["Choose a spectrum color", "اختيار لون من الطيف"],
    "اندازه‌گیری وسیله": ["Device readings", "قراءات الجهاز"],
    "انرژی مصرف‌شده": ["Energy used", "الطاقة المستهلكة"],
    "به‌روزرسانی تغذیه": ["Refresh power status", "تحديث حالة الطاقة"],
    "تأیید شد": ["Confirmed", "مؤكد"],
    "تأیید نشد": ["Not confirmed", "غير مؤكد"],
    "تا پایان اعتبار قبلی صبر کن": [
      "Wait for the previous code to expire",
      "انتظر انتهاء صلاحية الرمز السابق",
    ],
    "تنظیمات خروجی": ["Output settings", "إعدادات المخرج"],
    "توان فعلی": ["Current power", "القدرة الحالية"],
    "جریان": ["Current", "التيار"],
    "جمعه": ["Friday", "الجمعة"],
    "حداقل یک روز را انتخاب کن.": [
      "Choose at least one day.",
      "اختر يومًا واحدًا على الأقل.",
    ],
    "حذف از این گوشی": ["Remove from this phone", "إزالة من هذا الهاتف"],
    "حذف فقط از این گوشی؟": [
      "Remove from this phone only?",
      "الإزالة من هذا الهاتف فقط؟",
    ],
    "حذف وسیله از مانیسا؟": [
      "Remove device from Manisa?",
      "إزالة الجهاز من مانیسا؟",
    ],
    "خاموش شود": ["Turn off", "إيقاف"],
    "خروجی": ["Output", "مخرج"],
    "در حال آماده‌سازی…": ["Preparing…", "جارٍ التجهيز…"],
    "در حال اتصال": ["Connecting", "جارٍ الاتصال"],
    "در حال امتحان…": ["Testing…", "جارٍ الاختبار…"],
    "در حال انجام": ["Working", "جارٍ التنفيذ"],
    "در حال بررسی…": ["Checking…", "جارٍ التحقق…"],
    "در حال جست‌وجو…": ["Searching…", "جارٍ البحث…"],
    "در حال خواندن زمان‌بندی‌ها…": [
      "Loading schedules…",
      "جارٍ تحميل الجداول…",
    ],
    "در حال خواندن سناریوها…": ["Loading scenes…", "جارٍ تحميل المشاهد…"],
    "در حال دریافت…": ["Reading…", "جارٍ الاستلام…"],
    "در دسترس": ["Available", "متاح"],
    "دوشنبه": ["Monday", "الاثنين"],
    "رنگ انتخاب‌شده برای سناریو": ["Selected scene color", "لون المشهد المحدد"],
    "رنگ دریافت‌شده از وسیله": [
      "Color received from device",
      "اللون المستلم من الجهاز",
    ],
    "روشن شود": ["Turn on", "تشغيل"],
    "زمان‌بندی‌ها خوانده نشدند؛ دوباره تلاش کن.": [
      "Schedules could not be loaded. Try again.",
      "تعذر تحميل الجداول. حاول مجددًا.",
    ],
    "ساخت کد موقت": ["Create temporary code", "إنشاء رمز مؤقت"],
    "سناریو ذخیره نشد. دوباره تلاش کن.": [
      "Scene was not saved. Try again.",
      "لم يُحفظ المشهد. حاول مجددًا.",
    ],
    "سناریوها خوانده نشدند؛ دوباره تلاش کن.": [
      "Scenes could not be loaded. Try again.",
      "تعذر تحميل المشاهد. حاول مجددًا.",
    ],
    "سناریوی حذف‌شده": ["Deleted scene", "مشهد محذوف"],
    "سه‌شنبه": ["Tuesday", "الثلاثاء"],
    "شبکه‌ای پیدا نشد؛ دوباره جست‌وجو کن یا نام را دستی وارد کن.": [
      "No networks found. Search again or enter the name.",
      "لم يُعثر على شبكات. ابحث مجددًا أو أدخل الاسم.",
    ],
    "شنبه": ["Saturday", "السبت"],
    "متوقف شد": ["Stopped", "متوقف"],
    "مثلاً خروجی ۱ اتاق کودک": [
      "For example, Bedroom output 1",
      "مثلاً، المخرج 1 لغرفة الطفل",
    ],
    "مصرف برق": ["Energy usage", "استهلاك الكهرباء"],
    "نام و بین یک تا ۳۲ خروجی انتخاب کن.": [
      "Add a name and choose 1 to 32 outputs.",
      "أدخل اسمًا واختر من 1 إلى 32 مخرجًا.",
    ],
    "نتیجه نامشخص": ["Unconfirmed result", "نتيجة غير مؤكدة"],
    "نور و مصرف": ["Lighting and energy", "الإضاءة والطاقة"],
    "وای‌فای": ["Wi-Fi", "واي فاي"],
    "ورودی برق متصل است": ["Power supply connected", "مصدر الطاقة موصول"],
    "ورودی برق متصل نیست": [
      "Power supply disconnected",
      "مصدر الطاقة غير موصول",
    ],
    "وسیلهٔ خانه": ["Home device", "جهاز المنزل"],
    "ولتاژ": ["Voltage", "الجهد"],
    "ویرایش زمان‌بندی": ["Edit schedule", "تعديل الجدول"],
    "ویرایش سناریو": ["Edit scene", "تعديل المشهد"],
    "پنجشنبه": ["Thursday", "الخميس"],
    "پیش‌نمایش رنگ": ["Color preview", "معاينة اللون"],
    "چهارشنبه": ["Wednesday", "الأربعاء"],
    "کد NFC دریافت شد.": ["NFC code received.", "تم استلام رمز NFC."],
    "گوشی را نزدیک تگ NFC وسیله نگه دار…": [
      "Hold your phone near the device's NFC tag…",
      "قرّب هاتفك من علامة NFC على الجهاز…",
    ],
    "یک نام برای خروجی بنویس.": ["Enter an output name.", "أدخل اسمًا للمخرج."],
    "یک نام برای وسیله بنویس.": ["Enter a device name.", "أدخل اسمًا للجهاز."],
    "یکشنبه": ["Sunday", "الأحد"],
    "۱ · انتخاب خروجی‌ها": ["1 · Choose outputs", "1 · اختيار المخارج"],
    "۲ · تنظیم عملکرد": ["2 · Set actions", "2 · تعيين الإجراءات"],
    "۲٫۴ گیگاهرتز": ["2.4 GHz", "2.4 غيغاهرتز"],
    "۵ یا ۶ گیگاهرتز؛ سازگاری وسیله را بررسی کن": [
      "5 or 6 GHz; check device compatibility",
      "5 أو 6 غيغاهرتز؛ تحقق من توافق الجهاز",
    ],
    "دسترسی جست‌وجو داده نشد؛ آن را در تنظیمات گوشی فعال کن.": [
      "Discovery permission denied. Enable it in phone settings.",
      "لم يُمنح إذن البحث. فعّله في إعدادات الهاتف.",
    ],
    "وای‌فای و موقعیت گوشی را روشن کن و دوباره جست‌وجو کن.": [
      "Turn on Wi-Fi and location, then search again.",
      "شغّل واي فاي والموقع، ثم ابحث مجددًا.",
    ],
    "بلوتوث گوشی را روشن کن.": [
      "Turn on your phone's Bluetooth.",
      "شغّل بلوتوث الهاتف.",
    ],
    "NFC در دسترس نیست؛ آن را روشن کن یا از QR استفاده کن.": [
      "NFC is unavailable. Turn it on or use QR.",
      "NFC غير متاح. شغّله أو استخدم QR.",
    ],
    "تگ باید حاوی کد اتصال Matter باشد.": [
      "The tag must contain a Matter setup code.",
      "يجب أن تحتوي العلامة على رمز إعداد Matter.",
    ],
    "کد اتصال متعلق به وسیلهٔ انتخاب‌شده نیست.": [
      "This setup code does not match the selected device.",
      "رمز الإعداد لا يطابق الجهاز المحدد.",
    ],
    "جست‌وجو لغو شد.": ["Search cancelled.", "أُلغي البحث."],
    "عملیات کامل نشد؛ اتصال و دسترسی‌ها را بررسی کن و دوباره تلاش کن.": [
      "This step did not finish. Check your connection and permissions, then try again.",
      "لم تكتمل هذه الخطوة. تحقق من الاتصال والأذونات ثم حاول مجددًا.",
    ],
  };
}

/// Explicitly localized product copy. User-entered names continue to use Text.
class AppText extends StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.textDirection,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
    this.textScaler,
    this.strutStyle,
    this.textWidthBasis,
    this.textHeightBehavior,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;
  final TextScaler? textScaler;
  final StrutStyle? strutStyle;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  @override
  Widget build(BuildContext context) {
    final copy = ManisaCopy.of(context);
    return Text(
      copy.text(data),
      style: style,
      textAlign: textAlign,
      textDirection: textDirection,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      semanticsLabel: semanticsLabel == null
          ? null
          : copy.text(semanticsLabel!),
      textScaler: textScaler,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
    );
  }
}

extension ManisaTranslation on BuildContext {
  String tr(String source) => ManisaCopy.of(this).text(source);
}
