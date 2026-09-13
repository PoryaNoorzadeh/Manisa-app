from __future__ import annotations

import datetime as dt
import hashlib
from pathlib import Path
import tempfile
import unittest

import m1_runner


class M1RunnerTests(unittest.TestCase):
    def test_versioned_run_stem_is_stable(self) -> None:
        started = dt.datetime(2026, 9, 13, 7, 30, tzinfo=dt.timezone.utc)
        self.assertEqual(
            m1_runner.run_stem(started),
            "manisa-m1-testbed-v0.2.0-run-20260913T073000Z",
        )

    def test_sha256_file_uses_actual_apk_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            apk = Path(raw) / "manisa-m1-v0.7.0-build10-arm64-release.apk"
            apk.write_bytes(b"test-apk")
            self.assertEqual(
                m1_runner.sha256_file(apk),
                hashlib.sha256(b"test-apk").hexdigest(),
            )

    def test_parse_adb_devices_keeps_only_authorized_devices(self) -> None:
        output = """List of devices attached
ABC123 device product:test model:Pixel transport_id:1
OFFLINE offline transport_id:2
UNAUTHORIZED unauthorized transport_id:3

"""
        self.assertEqual(m1_runner.parse_adb_devices(output), ["ABC123"])

    def test_resolve_tests_preserves_requested_order(self) -> None:
        selected = m1_runner.resolve_tests("M1-T20,M1-T09")
        self.assertEqual(
            [case.test_id for case in selected],
            ["M1-T20", "M1-T09"],
        )
        with self.assertRaises(m1_runner.RunnerError):
            m1_runner.resolve_tests("M1-UNKNOWN")
        self.assertEqual(m1_runner.resolve_tests("none"), [])

    def test_resolve_performance_cases_and_reject_unknown(self) -> None:
        selected = m1_runner.resolve_performance_cases("M1-P03,M1-P01")
        self.assertEqual([case.test_id for case in selected], ["M1-P03", "M1-P01"])
        self.assertEqual(m1_runner.resolve_performance_cases("none"), [])
        with self.assertRaises(m1_runner.RunnerError):
            m1_runner.resolve_performance_cases("M1-P99")

    def test_percentile_uses_linear_interpolation(self) -> None:
        self.assertEqual(m1_runner.percentile([1, 2, 3, 4, 5], 50), 3)
        self.assertAlmostEqual(m1_runner.percentile([1, 2, 3, 4, 5], 95), 4.8)
        with self.assertRaises(ValueError):
            m1_runner.percentile([], 95)

    def test_performance_summary_enforces_sample_count_and_target(self) -> None:
        case = m1_runner._PERFORMANCE_BY_ID["M1-P01"]
        passing = [
            {"status": "PASS", "duration_seconds": value}
            for value in (1.0, 1.2, 1.4, 1.6, 1.8)
        ]
        summary = m1_runner.summarize_performance(case, passing, 5)
        self.assertEqual(summary["status"], "PASS")
        self.assertTrue(summary["target_met"])

        incomplete = m1_runner.summarize_performance(case, passing[:4], 5)
        self.assertEqual(incomplete["status"], "FAIL")
        self.assertFalse(incomplete["target_met"])

    def test_capture_device_log_keeps_only_new_redacted_content(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            source = Path(raw) / "firmware.log"
            destination = Path(raw) / "device-serial.log"
            source.write_text("old line\n", encoding="utf-8")
            offset = source.stat().st_size
            with source.open("a", encoding="utf-8") as target:
                target.write("new password=secret MT:Y.K9042C00KA0648G00\n")
            m1_runner.capture_device_log_segment(source, offset, destination)
            captured = destination.read_text(encoding="utf-8")
        self.assertNotIn("old line", captured)
        self.assertNotIn("secret", captured)
        self.assertNotIn("K9042C00KA0648G00", captured)

    def test_sensitive_setup_data_is_redacted(self) -> None:
        note = "password=secret MT:Y.K9042C00KA0648G00"
        sanitized = m1_runner.sanitize_note(note)
        self.assertNotIn("secret", sanitized)
        self.assertNotIn("K9042C00KA0648G00", sanitized)
        self.assertIn("[REDACTED]", sanitized)

    def test_installed_version_parsing(self) -> None:
        dump = "versionCode=10 minSdk=28 targetSdk=35\nversionName=0.7.0"
        self.assertEqual(m1_runner.installed_version(dump), "0.7.0+10")
        self.assertEqual(m1_runner.installed_version("not installed"), "not-installed")

    def test_report_contains_machine_and_human_results(self) -> None:
        metadata = {
            "runner_version": "0.2.0",
            "run_id": "manisa-m1-testbed-v0.2.0-run-20260913T073000Z",
            "started_at": "2026-09-13T07:30:00Z",
            "finished_at": "2026-09-13T07:35:00Z",
            "apk_filename": "manisa-m1-v0.7.0-build10-arm64-release.apk",
            "apk_sha256": "abc",
            "adb_device_id": "e0bebd228199",
            "manufacturer": "Google",
            "model": "Pixel",
            "android_version": "16",
            "android_sdk": "36",
            "installed_version": "0.7.0+10",
        }
        results = [
            {
                "test_id": "M1-T09",
                "title": "Wi-Fi recovery",
                "status": "PASS",
                "duration_seconds": 12.5,
                "note": "recovered",
            },
            {
                "test_id": "M1-T10",
                "title": "Power cycle",
                "status": "BLOCKED",
                "duration_seconds": 0,
                "note": "",
            },
        ]
        performance_results = [
            {
                "test_id": "M1-P01",
                "title": "Command latency",
                "summary": {
                    "pass_count": 30,
                    "requested_samples": 30,
                    "median_seconds": 0.8,
                    "p95_seconds": 1.4,
                    "max_seconds": 1.6,
                    "success_rate_percent": 100.0,
                    "target_metric": "p95",
                    "target_seconds": 2.0,
                    "status": "PASS",
                },
            }
        ]
        with tempfile.TemporaryDirectory() as raw:
            report = Path(raw) / "report.md"
            m1_runner.write_report(report, metadata, results, performance_results)
            text = report.read_text(encoding="utf-8")
        self.assertIn("| 1 | 0 | 1 | 0 |", text)
        self.assertIn("M1-T09", text)
        self.assertIn("M1-T10", text)
        self.assertIn("adb-logcat.txt", text)
        self.assertNotIn("ABC123", text)
        self.assertIn("e0bebd228199", text)
        self.assertIn("M1-P01", text)
        self.assertIn("1.4s", text)
        self.assertIn("timeline.jsonl", text)


if __name__ == "__main__":
    unittest.main()
