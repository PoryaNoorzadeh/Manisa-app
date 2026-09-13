# راهنمای Manisa M1 Test Bed Runner

نسخه Runner: **0.2.0**

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

اجرای تست‌های عملکردی ضروری بدون اجرای تست‌های فانکشنال:

```bash
python3 tools/testbed/m1_runner.py \
  --apk /path/to/manisa-m1-v0.7.0-build10-arm64-release.apk \
  --tests none \
  --benchmarks M1-P01,M1-P02,M1-P03
```

تعداد تکرار پیش‌فرض P01 برابر ۳۰ و P02/P03 برابر ۵ است. برای یک اجرای آزمایشی کوتاه می‌توان تعداد همه benchmarkهای انتخابی را تغییر داد؛ چنین اجرایی جای اجرای کامل پذیرش را نمی‌گیرد:

```bash
python3 tools/testbed/m1_runner.py \
  --apk /path/to/app.apk \
  --tests none \
  --benchmarks M1-P01 \
  --samples 3
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

## تست‌های عملکردی

| شناسه | سناریو | تکرار پذیرش | معیار اولیه |
|---|---|---:|---|
| M1-P01 | فرمان اپ تا تأیید وضعیت واقعی | ۳۰ | p95 حداکثر ۲ ثانیه و همه نمونه‌ها موفق |
| M1-P02 | Retry تا اولین خواندن یا فرمان موفق | ۵ | بیشینه حداکثر ۱۵ ثانیه و همه نمونه‌ها موفق |
| M1-P03 | Commission تا اولین کنترل موفق | ۵ | پنج اجرای موفق از پنج اجرا |

زمان‌گیری نسخه 0.2.0 هدایت‌شده است: اپراتور در لحظه شروع و مشاهده معیار پایان Enter می‌زند. بنابراین عدد شامل تأخیر واکنش اپراتور است و «latency داخلی پروتکل» محسوب نمی‌شود؛ برای سنجش پذیرش تجربه واقعی کاربر، عددی محافظه‌کارانه و قابل تکرار می‌دهد.

### تطبیق با لاگ فریمور

اگر ابزار serial جداگانه لاگ device را به یک فایل append می‌کند، مسیر آن را به Runner بدهید:

```bash
python3 tools/testbed/m1_runner.py \
  --apk /path/to/app.apk \
  --tests none \
  --benchmarks M1-P01 \
  --device-log-file /path/to/firmware.log
```

Runner فقط داده‌ای را که پس از شروع اجرا به فایل اضافه شده در `device-serial.log` کپی می‌کند. `timeline.jsonl` برای شروع و پایان هر تست و نمونه، timestamp UTC و elapsed monotonic ثبت می‌کند. برای هم‌بستگی دقیق، ابزار serial باید timestamp داشته باشد و ساعت لپ‌تاپ صحیح باشد.

## خروجی نسخه‌دار

هر اجرا پوشه‌ای با این الگو می‌سازد:

```text
test-results/
└── manisa-m1-testbed-v0.2.0-run-YYYYMMDDTHHMMSSZ/
    ├── adb-logcat.txt
    ├── device-serial.log          # اختیاری
    ├── metadata.json
    ├── package-dump.txt
    ├── performance.json
    ├── results.json
    ├── timeline.jsonl
    └── manisa-m1-testbed-v0.2.0-run-YYYYMMDDTHHMMSSZ-report.md
```

Metadata شامل نسخه Runner، نام و SHA-256 APK، شناسهٔ هش‌شدهٔ گوشی، مدل گوشی، نسخه Android، نسخه نصب‌شده و زمان UTC است. serial خام و مسیر کامل فایل روی لپ‌تاپ ذخیره نمی‌شوند.

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

## محدوده نسخه 0.2.0

این نسخه علاوه بر preflight، نصب اختیاری، restart اپ، logcat و گزارش فانکشنال نسخه 0.1.0، سه benchmark پذیرش، محاسبه median/p95/max/success-rate، timeline ماشینی و برش لاگ سریال خارجی را پوشش می‌دهد.

کنترل رله، برق روتر یا device عمداً خودکار نشده است. نتیجه benchmark فقط پس از اجرای کامل روی گوشی و device واقعی معتبر است. CI صرفاً منطق محاسبه و تولید گزارش را تأیید می‌کند.
