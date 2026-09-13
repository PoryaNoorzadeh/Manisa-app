# راهنمای Manisa M1 Test Bed Runner

نسخه Runner: **0.1.0**

این ابزار تست‌های سخت‌افزاری M1 را روی گوشی Android به‌صورت هدایت‌شده اجرا و شواهد هر اجرا را با نام نسخه‌دار ذخیره می‌کند. مرجع وضعیت تست‌ها همچنان [M1-test-register.md](M1-test-register.md) است.

## پیش‌نیازها

- Python 3.10 یا جدیدتر
- Android Platform Tools و فرمان `adb` در PATH
- اتصال USB و فعال‌بودن USB debugging
- دقیقاً یک گوشی authorize‌شده؛ برای چند گوشی از `--serial` استفاده شود
- APK نسخه‌دار مانیسا
- برای تست Matter، گوشی و device روی شبکه مناسب تست باشند

Runner رمز Wi-Fi یا QR را درخواست نمی‌کند. این اطلاعات را در یادداشت تست نیز وارد نکنید؛ الگوهای شناخته‌شده پیش از ذخیره redacted می‌شوند.

## اجرای سریع

Linux/macOS:

```bash
python3 tools/testbed/m1_runner.py \
  --apk /path/to/manisa-m1-v0.7.0-build10-arm64-release.apk
```

Windows PowerShell:

```powershell
py tools/testbed/m1_runner.py --apk C:\path\manisa-m1-v0.7.0-build10-arm64-release.apk
```

برای نصب یا به‌روزرسانی همان APK پیش از تست:

```bash
python3 tools/testbed/m1_runner.py \
  --apk /path/to/manisa-m1-v0.7.0-build10-arm64-release.apk \
  --install
```

بدون `--install` هیچ APKای روی گوشی نصب نمی‌شود.

## انتخاب تست‌ها

اجرای مجموعه ضروری پیش‌فرض:

```bash
python3 tools/testbed/m1_runner.py --apk /path/to/app.apk
```

اجرای چند تست مشخص:

```bash
python3 tools/testbed/m1_runner.py \
  --apk /path/to/app.apk \
  --tests M1-T09,M1-T10,M1-T11
```

جمع‌آوری metadata بدون اجرای دستی تست:

```bash
python3 tools/testbed/m1_runner.py \
  --apk /path/to/app.apk \
  --non-interactive
```

اگر چند گوشی متصل هستند:

```bash
python3 tools/testbed/m1_runner.py \
  --apk /path/to/app.apk \
  --serial DEVICE_SERIAL
```

## تست‌های پشتیبانی‌شده

| شناسه | سناریو |
|---|---|
| M1-T06 | تغییر فیزیکی در زمان بازبودن اپ |
| M1-T07 | تغییر فیزیکی در زمان بسته‌بودن اپ |
| M1-T08 | تطبیق تمام endpointها و رله‌ها |
| M1-T09 | قطع و وصل Wi-Fi گوشی |
| M1-T10 | قطع و وصل برق device |
| M1-T11 | Force-stop و اجرای دوباره اپ |
| M1-T12 | حذف device آفلاین |
| M1-T15 | کنترل محلی بدون اینترنت |
| M1-T18 | ماندگاری نام device |
| M1-T19 | نام‌گذاری و امتحان خروجی‌ها |
| M1-T20 | یک device آنلاین و یک device آفلاین |

تغییر Wi-Fi، برق و وضعیت فیزیکی توسط اپراتور انجام می‌شود. Runner این اعمال را خودکار نمی‌کند. تنها عمل خودکار روی گوشی، اجرای مجدد اپ در T11 است.

## خروجی نسخه‌دار

هر اجرا پوشه‌ای با این الگو می‌سازد:

```text
test-results/
└── manisa-m1-testbed-v0.1.0-run-YYYYMMDDTHHMMSSZ/
    ├── adb-logcat.txt
    ├── metadata.json
    ├── package-dump.txt
    ├── results.json
    └── manisa-m1-testbed-v0.1.0-run-YYYYMMDDTHHMMSSZ-report.md
```

Metadata شامل نسخه Runner، نام و SHA-256 APK، serial گوشی، مدل گوشی، نسخه Android، نسخه نصب‌شده و زمان UTC است.

نتیجه هر تست یکی از این چهار مقدار است:

- `PASS`: معیار قبولی روی سخت‌افزار مشاهده شده است.
- `FAIL`: نتیجه واقعی با معیار قبولی مغایرت دارد.
- `BLOCKED`: پیش‌نیاز تست فراهم نبوده یا اجرا کامل نشده است.
- `NOT_RUN`: تست اجرا نشده است.

`BLOCKED` و `NOT_RUN` هیچ‌وقت معادل موفقیت نیستند.

## ثبت نتیجه در رجیستر

پس از اجرا:

1. گزارش Markdown را بازبینی کنید.
2. رمز، QR، SSID خصوصی، IP عمومی و اطلاعات نامرتبط را منتشر نکنید.
3. نتیجه هر شناسه، نسخه APK، مدل گوشی و نسخه فریمور device را در `M1-test-register.md` ثبت کنید.
4. لاگ خام را فقط در فضای خصوصی نگه دارید؛ برای issue عمومی بخش لازم و پاک‌سازی‌شده را جدا کنید.
5. اگر تست FAIL شد، مراحل، انتظار، نتیجه واقعی و timestamp متناظر logcat ثبت شود.

## محدوده نسخه 0.1.0

این نسخه preflight، نصب اختیاری، restart اپ، logcat و گزارش هدایت‌شده را پوشش می‌دهد. کنترل رله، برق روتر یا device عمداً خودکار نشده است. اندازه‌گیری خودکار latency فرمان و هم‌بستگی لاگ سریال device در نسخه بعدی Runner توسعه می‌یابد.
