#!/usr/bin/env python3
"""Guided Manisa M1 hardware test-bed runner.

Collects reproducible APK/device metadata, ADB logs and explicit manual
PASS/FAIL/BLOCKED/NOT_RUN results. It never toggles Wi-Fi, power, or installs an
APK unless the operator explicitly requests the install with --install.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from typing import Sequence

RUNNER_VERSION = "0.2.0"
PACKAGE_NAME = "com.manisa.manisa_mobile"
MAIN_ACTIVITY = f"{PACKAGE_NAME}/.MainActivity"
VALID_RESULTS = ("PASS", "FAIL", "BLOCKED", "NOT_RUN")


@dataclasses.dataclass(frozen=True)
class TestCase:
    test_id: str
    title: str
    instructions: tuple[str, ...]
    automated_action: str | None = None


@dataclasses.dataclass(frozen=True)
class PerformanceCase:
    test_id: str
    title: str
    instructions: tuple[str, ...]
    default_samples: int
    metric: str
    target_seconds: float | None = None


TEST_CASES: tuple[TestCase, ...] = (
    TestCase(
        "M1-T06",
        "تغییر فیزیکی در زمان بازبودن اپ",
        (
            "اپ و کارت دستگاه را باز نگه دار.",
            "هر خروجی را یک‌بار از روی کلید فیزیکی تغییر بده.",
            "بررسی کن فقط همان خروجی بدون Refresh دستی به‌روز شود.",
        ),
    ),
    TestCase(
        "M1-T07",
        "تغییر فیزیکی در زمان بسته‌بودن اپ",
        (
            "اپ را به پس‌زمینه ببر و خروجی را از روی کلید تغییر بده.",
            "به اپ برگرد و تطبیق وضعیت واقعی و نمایش اپ را بررسی کن.",
        ),
    ),
    TestCase(
        "M1-T08",
        "تطبیق تمام endpointها با رله‌ها",
        (
            "تمام خروجی‌ها را جداگانه از داخل اپ روشن و خاموش کن.",
            "ثبت کن هر endpoint فقط کدام رله را تغییر می‌دهد.",
        ),
    ),
    TestCase(
        "M1-T09",
        "قطع و وصل Wi-Fi گوشی",
        (
            "Wi-Fi گوشی را دستی قطع کن و Refresh را بزن.",
            "پس از مشاهده وضعیت «در دسترس نیست»، Wi-Fi را وصل کن.",
            "«تلاش دوباره» را بزن؛ دستگاه باید بدون Commission مجدد برگردد.",
        ),
    ),
    TestCase(
        "M1-T10",
        "قطع و وصل برق دستگاه",
        (
            "برق دستگاه را با روش ایمن قطع و دوباره وصل کن.",
            "حفظ Fabric، وضعیت پیش‌فرض رله و زمان بازیابی را ثبت کن.",
            "Retry نباید به Commission مجدد نیاز داشته باشد.",
        ),
    ),
    TestCase(
        "M1-T11",
        "Force-stop و اجرای دوباره اپ",
        (
            "Runner اپ را Force-stop و دوباره اجرا می‌کند.",
            "باقی‌ماندن device و موفقیت اولین خواندن و فرمان را بررسی کن.",
        ),
        automated_action="restart_app",
    ),
    TestCase(
        "M1-T12",
        "حذف دستگاه آفلاین",
        (
            "پس از خاموش‌کردن دستگاه، حذف را از داخل اپ درخواست کن.",
            "اپ نباید موفقیت کاذب نشان دهد و رکورد باید باقی بماند.",
        ),
    ),
    TestCase(
        "M1-T15",
        "کار محلی بدون اینترنت",
        (
            "WAN روتر را قطع کن ولی LAN و Wi-Fi داخلی را روشن نگه دار.",
            "خواندن و کنترل device موجود را بررسی کن.",
        ),
    ),
    TestCase(
        "M1-T18",
        "ماندگاری نام device",
        (
            "نام device را تغییر بده، اپ را ببند و دوباره باز کن.",
            "نام باید بدون تغییر باقی مانده باشد.",
        ),
    ),
    TestCase(
        "M1-T19",
        "نام‌گذاری و امتحان خروجی‌ها",
        (
            "برای هر خروجی نام مستقل ثبت و «امتحان این خروجی» را اجرا کن.",
            "پس از بازکردن مجدد اپ، نام و تطبیق endpoint را بررسی کن.",
        ),
    ),
    TestCase(
        "M1-T20",
        "جداسازی دو دستگاه",
        (
            "دو device را اضافه کن و یکی را آفلاین کن.",
            "device سالم باید قابل کنترل بماند.",
            "Retry کارت آفلاین نباید وضعیت device سالم را مختل کند.",
        ),
    ),
)

DEFAULT_TEST_IDS = tuple(case.test_id for case in TEST_CASES)
_TEST_BY_ID = {case.test_id: case for case in TEST_CASES}

PERFORMANCE_CASES: tuple[PerformanceCase, ...] = (
    PerformanceCase(
        "M1-P01",
        "زمان فرمان تا تأیید وضعیت",
        (
            "Enter را بزن و بلافاصله فرمان روشن/خاموش را در اپ اجرا کن.",
            "وقتی وضعیت واقعی رله و اپ تأیید شد دوباره Enter بزن.",
        ),
        default_samples=30,
        metric="p95",
        target_seconds=2.0,
    ),
    PerformanceCase(
        "M1-P02",
        "زمان بازیابی پس از Retry",
        (
            "دستگاه را در وضعیت unavailable قرار بده.",
            "Enter را بزن و بلافاصله «تلاش دوباره» را اجرا کن.",
            "بعد از اولین خواندن یا فرمان موفق دوباره Enter بزن.",
        ),
        default_samples=5,
        metric="max",
        target_seconds=15.0,
    ),
    PerformanceCase(
        "M1-P03",
        "زمان Commission تا اولین کنترل",
        (
            "دستگاه Factory Reset شده را در حالت Pairing آماده کن.",
            "Enter را بزن و بلافاصله افزودن دستگاه را شروع کن.",
            "پس از اولین کنترل موفق دوباره Enter بزن.",
        ),
        default_samples=5,
        metric="success_rate",
    ),
)

_PERFORMANCE_BY_ID = {case.test_id: case for case in PERFORMANCE_CASES}


class RunnerError(RuntimeError):
    pass


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso_utc(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def run_stem(started_at: dt.datetime) -> str:
    stamp = started_at.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"manisa-m1-testbed-v{RUNNER_VERSION}-run-{stamp}"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sanitize_note(value: str) -> str:
    value = re.sub(
        r"(?i)((?:wi-?fi\s*)?password|passphrase|رمز(?:\s+وای.?فای)?)\s*[:=]\s*\S+",
        r"\1=[REDACTED]",
        value,
    )
    return re.sub(r"(?i)\bMT:[A-Z0-9.+/_-]+", "MT:[REDACTED]", value)


def parse_adb_devices(output: str) -> list[str]:
    serials: list[str] = []
    for raw_line in output.splitlines()[1:]:
        columns = raw_line.strip().split()
        if len(columns) >= 2 and columns[1] == "device":
            serials.append(columns[0])
    return serials


def command(
    args: Sequence[str],
    *,
    timeout: int = 30,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            list(args),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RunnerError(f"Command failed to start: {args[0]}: {error}") from error
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RunnerError(f"Command failed ({result.returncode}): {args[0]}: {detail}")
    return result


class Adb:
    def __init__(self, executable: str, serial: str) -> None:
        self.executable = executable
        self.serial = serial

    def args(self, *parts: str) -> list[str]:
        return [self.executable, "-s", self.serial, *parts]

    def run(
        self,
        *parts: str,
        timeout: int = 30,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return command(self.args(*parts), timeout=timeout, check=check)

    def shell(self, *parts: str, timeout: int = 30) -> str:
        return self.run("shell", *parts, timeout=timeout).stdout.strip()

    def property(self, key: str) -> str:
        return self.shell("getprop", key)

    def restart_app(self) -> None:
        self.run("shell", "am", "force-stop", PACKAGE_NAME)
        launched = self.run(
            "shell",
            "am",
            "start",
            "-n",
            MAIN_ACTIVITY,
            check=False,
        )
        if launched.returncode != 0 or "Error" in launched.stdout:
            self.run(
                "shell",
                "monkey",
                "-p",
                PACKAGE_NAME,
                "-c",
                "android.intent.category.LAUNCHER",
                "1",
            )


def resolve_tests(raw: str) -> list[TestCase]:
    if raw == "none":
        return []
    requested = DEFAULT_TEST_IDS if raw in ("default", "all") else tuple(
        item.strip().upper() for item in raw.split(",") if item.strip()
    )
    unknown = [test_id for test_id in requested if test_id not in _TEST_BY_ID]
    if unknown:
        raise RunnerError(f"Unknown test id(s): {', '.join(unknown)}")
    return [_TEST_BY_ID[test_id] for test_id in requested]


def resolve_performance_cases(raw: str) -> list[PerformanceCase]:
    if raw == "none":
        return []
    requested = (
        tuple(case.test_id for case in PERFORMANCE_CASES)
        if raw == "all"
        else tuple(item.strip().upper() for item in raw.split(",") if item.strip())
    )
    unknown = [test_id for test_id in requested if test_id not in _PERFORMANCE_BY_ID]
    if unknown:
        raise RunnerError(f"Unknown performance test id(s): {', '.join(unknown)}")
    return [_PERFORMANCE_BY_ID[test_id] for test_id in requested]


def percentile(values: Sequence[float], percentage: float) -> float:
    if not values:
        raise ValueError("percentile requires at least one value")
    if not 0 <= percentage <= 100:
        raise ValueError("percentage must be between 0 and 100")
    ordered = sorted(float(value) for value in values)
    position = (len(ordered) - 1) * percentage / 100
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def summarize_performance(
    case: PerformanceCase,
    samples: Sequence[dict[str, object]],
    requested_samples: int,
) -> dict[str, object]:
    passed = [
        float(sample["duration_seconds"])
        for sample in samples
        if sample["status"] == "PASS"
    ]
    completed = len(samples)
    pass_count = len(passed)
    summary: dict[str, object] = {
        "requested_samples": requested_samples,
        "completed_samples": completed,
        "pass_count": pass_count,
        "success_rate_percent": round(
            (pass_count / requested_samples * 100) if requested_samples else 0,
            2,
        ),
        "median_seconds": round(percentile(passed, 50), 3) if passed else None,
        "p95_seconds": round(percentile(passed, 95), 3) if passed else None,
        "max_seconds": round(max(passed), 3) if passed else None,
        "target_metric": case.metric,
        "target_seconds": case.target_seconds,
    }
    all_passed = completed == requested_samples and pass_count == requested_samples
    if case.metric == "success_rate":
        target_met = all_passed
    else:
        measured = summary[f"{case.metric}_seconds"]
        target_met = (
            all_passed
            and measured is not None
            and case.target_seconds is not None
            and float(measured) <= case.target_seconds
        )
    summary["target_met"] = target_met
    summary["status"] = "PASS" if target_met else "FAIL" if completed else "NOT_RUN"
    return summary


def choose_serial(adb_executable: str, requested: str | None) -> str:
    result = command([adb_executable, "devices", "-l"])
    connected = parse_adb_devices(result.stdout)
    if requested:
        if requested not in connected:
            raise RunnerError(
                f"Requested ADB device {requested!r} is not connected and authorized"
            )
        return requested
    if len(connected) != 1:
        raise RunnerError(
            "Exactly one authorized ADB device is required; "
            f"found {len(connected)}. Use --serial when more than one is connected."
        )
    return connected[0]


def prompt_result(case: TestCase) -> tuple[str, str]:
    print(f"\n[{case.test_id}] {case.title}")
    for index, instruction in enumerate(case.instructions, 1):
        print(f"  {index}. {instruction}")
    input("برای شروع این تست Enter بزن… ")
    while True:
        raw = input("نتیجه [p=PASS, f=FAIL, b=BLOCKED, s=NOT_RUN]: ").strip().lower()
        status = {"p": "PASS", "f": "FAIL", "b": "BLOCKED", "s": "NOT_RUN"}.get(raw)
        if status:
            break
        print("یکی از p، f، b یا s را وارد کن.")
    note = sanitize_note(input("یادداشت کوتاه (بدون رمز یا QR؛ اختیاری): ").strip())
    return status, note


def prompt_status(prompt: str = "نتیجه") -> str:
    while True:
        raw = input(f"{prompt} [p=PASS, f=FAIL, b=BLOCKED, s=NOT_RUN]: ").strip().lower()
        status = {"p": "PASS", "f": "FAIL", "b": "BLOCKED", "s": "NOT_RUN"}.get(raw)
        if status:
            return status
        print("یکی از p، f، b یا s را وارد کن.")


class TimelineRecorder:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.started = time.perf_counter()

    def record(self, event: str, **fields: object) -> None:
        item = {
            "timestamp": iso_utc(utc_now()),
            "elapsed_seconds": round(time.perf_counter() - self.started, 6),
            "event": event,
            **fields,
        }
        with self.path.open("a", encoding="utf-8") as target:
            target.write(json.dumps(item, ensure_ascii=False) + "\n")


def run_performance_case(
    case: PerformanceCase,
    sample_count: int,
    timeline: TimelineRecorder,
) -> dict[str, object]:
    print(f"\n[{case.test_id}] {case.title} — {sample_count} تکرار")
    for index, instruction in enumerate(case.instructions, 1):
        print(f"  {index}. {instruction}")
    samples: list[dict[str, object]] = []
    for sample_number in range(1, sample_count + 1):
        input(f"\nنمونه {sample_number}/{sample_count}: برای شروع Enter بزن… ")
        sample_started_at = utc_now()
        started = time.perf_counter()
        timeline.record(
            "performance_sample_started",
            test_id=case.test_id,
            sample=sample_number,
        )
        input("پس از مشاهده معیار پایان، فوراً Enter بزن… ")
        duration = round(time.perf_counter() - started, 3)
        status = prompt_status("اعتبار این نمونه")
        note = sanitize_note(input("یادداشت کوتاه (اختیاری): ").strip())
        sample = {
            "sample": sample_number,
            "status": status,
            "duration_seconds": duration,
            "started_at": iso_utc(sample_started_at),
            "finished_at": iso_utc(utc_now()),
            "note": note,
        }
        samples.append(sample)
        timeline.record(
            "performance_sample_finished",
            test_id=case.test_id,
            sample=sample_number,
            status=status,
            duration_seconds=duration,
        )
    return {
        "test_id": case.test_id,
        "title": case.title,
        "samples": samples,
        "summary": summarize_performance(case, samples, sample_count),
    }


def capture_device_log_segment(source: Path, start_offset: int, destination: Path) -> None:
    with source.open("rb") as raw:
        raw.seek(start_offset)
        text = raw.read().decode("utf-8", errors="replace")
    destination.write_text(sanitize_note(text), encoding="utf-8")


def write_json(path: Path, value: object) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def write_report(
    path: Path,
    metadata: dict[str, object],
    results: list[dict[str, object]],
    performance_results: list[dict[str, object]] | None = None,
) -> None:
    performance_results = performance_results or []
    counts = {status: 0 for status in VALID_RESULTS}
    for result in results:
        counts[str(result["status"])] += 1
    lines = [
        "# گزارش Test Bed مانیسا M1",
        "",
        f"- Runner: `v{metadata['runner_version']}`",
        f"- Run ID: `{metadata['run_id']}`",
        f"- شروع: `{metadata['started_at']}`",
        f"- پایان: `{metadata.get('finished_at', 'در حال اجرا')}`",
        f"- APK: `{metadata['apk_filename']}`",
        f"- SHA-256: `{metadata['apk_sha256']}`",
        f"- شناسه گوشی: `{metadata['adb_device_id']}`",
        f"- گوشی: {metadata.get('manufacturer', '')} {metadata.get('model', '')}".rstrip(),
        f"- Android: `{metadata.get('android_version', '')}` (SDK {metadata.get('android_sdk', '')})",
        f"- نسخه نصب‌شده: `{metadata.get('installed_version', 'unknown')}`",
        "",
        "## خلاصه",
        "",
        "| PASS | FAIL | BLOCKED | NOT RUN |",
        "|---:|---:|---:|---:|",
        f"| {counts['PASS']} | {counts['FAIL']} | {counts['BLOCKED']} | {counts['NOT_RUN']} |",
        "",
        "## نتایج",
        "",
        "| شناسه | تست | نتیجه | مدت | یادداشت |",
        "|---|---|---|---:|---|",
    ]
    for result in results:
        note = str(result.get("note") or "—").replace("|", "\\|").replace("\n", " ")
        lines.append(
            f"| {result['test_id']} | {result['title']} | {result['status']} | "
            f"{result['duration_seconds']}s | {note} |"
        )
    if performance_results:
        lines.extend(
            (
                "",
                "## نتایج عملکرد",
                "",
                "| شناسه | نمونه موفق/درخواستی | Median | P95 | Max | Success rate | هدف | نتیجه |",
                "|---|---:|---:|---:|---:|---:|---|---|",
            )
        )
        for result in performance_results:
            summary = result["summary"]
            target = (
                "100% success"
                if summary["target_metric"] == "success_rate"
                else f"{summary['target_metric']} ≤ {summary['target_seconds']}s"
            )
            lines.append(
                f"| {result['test_id']} | {summary['pass_count']}/{summary['requested_samples']} | "
                f"{summary['median_seconds'] if summary['median_seconds'] is not None else '—'}s | "
                f"{summary['p95_seconds'] if summary['p95_seconds'] is not None else '—'}s | "
                f"{summary['max_seconds'] if summary['max_seconds'] is not None else '—'}s | "
                f"{summary['success_rate_percent']}% | {target} | {summary['status']} |"
            )
    lines.extend(
        (
            "",
            "## فایل‌های شاهد",
            "",
            "- `adb-logcat.txt`: لاگ کامل ADB در بازه اجرای تست",
            "- `package-dump.txt`: اطلاعات پکیج نصب‌شده",
            "- `metadata.json`: نسخه‌ها، دستگاه و checksum",
            "- `results.json`: نتیجه ساختاریافته تست‌ها",
            "- `performance.json`: نمونه‌ها و آمار تست‌های عملکردی انتخاب‌شده",
            "- `timeline.jsonl`: زمان UTC و زمان یکنواخت رخدادهای Runner برای تطبیق لاگ‌ها",
            "- `device-serial.log`: بخش متناظر لاگ خارجی device، در صورت استفاده از `--device-log-file`",
            "",
            "> نتیجه CI یا شبیه‌سازی جای تست سخت‌افزاری را نمی‌گیرد.",
            "",
        )
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def installed_version(package_dump: str) -> str:
    name = re.search(r"\bversionName=([^\s]+)", package_dump)
    code = re.search(r"\bversionCode=(\d+)", package_dump)
    if not name and not code:
        return "not-installed"
    return f"{name.group(1) if name else '?'}+{code.group(1) if code else '?'}"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Manisa M1 guided Android/Matter hardware test-bed runner"
    )
    parser.add_argument("--apk", required=True, type=Path, help="Versioned Manisa APK")
    parser.add_argument("--serial", help="ADB device serial; required when multiple devices exist")
    parser.add_argument(
        "--tests",
        default="default",
        help="default/all/none or comma-separated IDs, for example M1-T09,M1-T11",
    )
    parser.add_argument(
        "--benchmarks",
        default="none",
        help="none/all or comma-separated performance IDs: M1-P01,M1-P02,M1-P03",
    )
    parser.add_argument(
        "--samples",
        type=int,
        help="Override the default repetition count for every selected benchmark",
    )
    parser.add_argument(
        "--device-log-file",
        type=Path,
        help="Optional append-only firmware log; capture only bytes added during this run",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("test-results"),
        help="Parent directory for the versioned run folder",
    )
    parser.add_argument(
        "--install",
        action="store_true",
        help="Install/update the supplied APK with adb install -r before testing",
    )
    parser.add_argument(
        "--non-interactive",
        action="store_true",
        help="Collect metadata and mark selected tests NOT_RUN",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    apk = args.apk.expanduser().resolve()
    if not apk.is_file() or apk.suffix.lower() != ".apk":
        raise RunnerError(f"APK not found or invalid: {apk}")
    tests = resolve_tests(args.tests)
    performance_cases = resolve_performance_cases(args.benchmarks)
    if args.samples is not None and args.samples < 1:
        raise RunnerError("--samples must be at least 1")
    if not tests and not performance_cases:
        raise RunnerError("Select at least one functional test or benchmark")
    device_log_file = args.device_log_file.expanduser().resolve() if args.device_log_file else None
    if device_log_file is not None and not device_log_file.is_file():
        raise RunnerError(f"Device log file was not found: {device_log_file}")
    device_log_offset = device_log_file.stat().st_size if device_log_file else 0
    adb_executable = shutil.which("adb")
    if not adb_executable:
        raise RunnerError("adb was not found in PATH")
    serial = choose_serial(adb_executable, args.serial)
    adb = Adb(adb_executable, serial)

    started_at = utc_now()
    run_id = run_stem(started_at)
    output = args.output_root.expanduser().resolve() / run_id
    output.mkdir(parents=True, exist_ok=False)

    if args.install:
        install = adb.run("install", "-r", str(apk), timeout=180, check=False)
        (output / "install.txt").write_text(
            install.stdout + install.stderr,
            encoding="utf-8",
        )
        if install.returncode != 0:
            raise RunnerError(f"APK install failed; see {output / 'install.txt'}")

    package_dump = adb.shell("dumpsys", "package", PACKAGE_NAME)
    (output / "package-dump.txt").write_text(package_dump + "\n", encoding="utf-8")

    metadata: dict[str, object] = {
        "runner_version": RUNNER_VERSION,
        "run_id": run_id,
        "started_at": iso_utc(started_at),
        "apk_filename": apk.name,
        "apk_size_bytes": apk.stat().st_size,
        "apk_sha256": sha256_file(apk),
        "adb_device_id": hashlib.sha256(serial.encode("utf-8")).hexdigest()[:12],
        "manufacturer": adb.property("ro.product.manufacturer"),
        "model": adb.property("ro.product.model"),
        "android_version": adb.property("ro.build.version.release"),
        "android_sdk": adb.property("ro.build.version.sdk"),
        "installed_version": installed_version(package_dump),
        "selected_tests": [case.test_id for case in tests],
        "selected_benchmarks": [case.test_id for case in performance_cases],
        "device_log_capture": device_log_file is not None,
    }
    write_json(output / "metadata.json", metadata)
    timeline = TimelineRecorder(output / "timeline.jsonl")
    timeline.record("run_started", run_id=run_id)

    log_path = output / "adb-logcat.txt"
    adb.run("logcat", "-c", check=False)
    log_handle = log_path.open("w", encoding="utf-8")
    log_process = subprocess.Popen(
        adb.args("logcat", "-v", "threadtime"),
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
    )

    results: list[dict[str, object]] = []
    performance_results: list[dict[str, object]] = []
    try:
        adb.restart_app()
        for case in tests:
            case_started = utc_now()
            timeline.record("functional_test_started", test_id=case.test_id)
            if args.non_interactive:
                status, note = "NOT_RUN", "non-interactive metadata collection"
            else:
                if case.automated_action == "restart_app":
                    input("\nبرای اجرای Force-stop و بازکردن مجدد اپ Enter بزن… ")
                    adb.restart_app()
                status, note = prompt_result(case)
            case_finished = utc_now()
            results.append(
                {
                    "test_id": case.test_id,
                    "title": case.title,
                    "status": status,
                    "note": note,
                    "started_at": iso_utc(case_started),
                    "finished_at": iso_utc(case_finished),
                    "duration_seconds": round(
                        (case_finished - case_started).total_seconds(), 3
                    ),
                }
            )
            timeline.record(
                "functional_test_finished",
                test_id=case.test_id,
                status=status,
                duration_seconds=results[-1]["duration_seconds"],
            )
            write_json(output / "results.json", results)
            write_report(
                output / f"{run_id}-report.md",
                metadata,
                results,
                performance_results,
            )
        for case in performance_cases:
            if args.non_interactive:
                performance_result = {
                    "test_id": case.test_id,
                    "title": case.title,
                    "samples": [],
                    "summary": summarize_performance(
                        case,
                        [],
                        args.samples or case.default_samples,
                    ),
                }
            else:
                performance_result = run_performance_case(
                    case,
                    args.samples or case.default_samples,
                    timeline,
                )
            performance_results.append(performance_result)
            write_json(output / "performance.json", performance_results)
            write_report(
                output / f"{run_id}-report.md",
                metadata,
                results,
                performance_results,
            )
    finally:
        if log_process.poll() is None:
            log_process.terminate()
            try:
                log_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                log_process.kill()
                log_process.wait(timeout=5)
        log_handle.close()
        if device_log_file is not None:
            capture_device_log_segment(
                device_log_file,
                device_log_offset,
                output / "device-serial.log",
            )

    metadata["finished_at"] = iso_utc(utc_now())
    timeline.record("run_finished", run_id=run_id)
    write_json(output / "metadata.json", metadata)
    write_json(output / "results.json", results)
    write_json(output / "performance.json", performance_results)
    write_report(
        output / f"{run_id}-report.md",
        metadata,
        results,
        performance_results,
    )
    print(f"\nگزارش Test Bed آماده شد: {output}")
    failed = any(item["status"] == "FAIL" for item in results) or any(
        item["summary"]["status"] == "FAIL" for item in performance_results
    )
    return 2 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RunnerError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(3)
