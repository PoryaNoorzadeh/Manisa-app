package com.manisa.manisa_mobile

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.tech.Ndef
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Foreground, bounded discovery. Never exposes Wi-Fi credentials or unrelated BLE devices. */
internal class ManisaDiscovery(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var permissionAction: (() -> Unit)? = null
    private var cleanup: (() -> Unit)? = null
    private var generation = 0L
    private val timeout = Runnable { finishError("discovery_timeout", "جست‌وجو تمام شد؛ دوباره تلاش کن.") }

    fun permissionsResult(code: Int, results: IntArray): Boolean {
        if (code != 9201) return false
        val action = permissionAction
        permissionAction = null
        if (results.isNotEmpty() && results.all { it == PackageManager.PERMISSION_GRANTED }) {
            try { action?.invoke() } catch (_: Exception) { finishError("discovery_failed", "جست‌وجو انجام نشد.") }
        } else finishError("permission_denied", "برای جست‌وجو دسترسی لازم را در تنظیمات گوشی فعال کن.")
        return true
    }

    private fun begin(result: MethodChannel.Result, permissions: List<String>, action: () -> Unit) {
        if (pending != null) { result.error("discovery_busy", "جست‌وجوی دیگری در حال اجراست.", null); return }
        pending = result
        generation++
        handler.postDelayed(timeout, 30000)
        val missing = permissions.filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        try {
            if (missing.isEmpty()) action() else {
                permissionAction = action
                activity.requestPermissions(missing.toTypedArray(), 9201)
            }
        } catch (_: Exception) { finishError("discovery_failed", "جست‌وجو انجام نشد؛ دسترسی‌ها را بررسی کن.") }
    }

    private fun finish(value: Any?) {
        val result = pending ?: return
        pending = null
        clear()
        result.success(value)
    }

    private fun finishError(code: String, message: String) {
        val result = pending ?: return
        pending = null
        clear()
        result.error(code, message, null)
    }

    private fun clear() {
        generation++
        handler.removeCallbacksAndMessages(null)
        permissionAction = null
        try { cleanup?.invoke() } catch (_: Exception) { }
        cleanup = null
    }

    fun cancel() { finishError("discovery_cancelled", "جست‌وجو لغو شد.") }

    @Suppress("DEPRECATION")
    fun wifi(result: MethodChannel.Result) = begin(result, listOf(
        Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)) {
        val requestGeneration = generation
        val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val location = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (!wifi.isWifiEnabled || !location.isLocationEnabled) {
            finishError("wifi_disabled", "برای نمایش شبکه‌ها، وای‌فای و موقعیت گوشی را روشن کن.")
            return@begin
        }
        fun respond(fresh: Boolean) {
            val networks = wifi.scanResults.filter { it.SSID.isNotEmpty() }
                .sortedByDescending { it.level }.distinctBy { it.SSID }
                .map { mapOf("ssid" to it.SSID, "rssi" to it.level, "frequency" to it.frequency,
                    "secured" to (it.capabilities.contains("WEP") || it.capabilities.contains("PSK") || it.capabilities.contains("SAE") || it.capabilities.contains("EAP"))) }
            finish(mapOf("networks" to networks, "fresh" to fresh))
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (pending == null || generation != requestGeneration) return
                try { respond(intent?.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false) == true) }
                catch (_: Exception) { finishError("wifi_scan_failed", "دریافت شبکه‌ها ناموفق بود.") }
            }
        }
        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= 33) activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else activity.registerReceiver(receiver, filter)
        cleanup = { activity.unregisterReceiver(receiver) }
        if (!wifi.startScan()) respond(false)
        else handler.postDelayed({ if (pending != null) respond(false) }, 10000)
    }

    fun bluetooth(result: MethodChannel.Result) = begin(result,
        if (Build.VERSION.SDK_INT >= 31) listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        else listOf(Manifest.permission.ACCESS_FINE_LOCATION)) {
        val requestGeneration = generation
        val adapter = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        val scanner = adapter?.bluetoothLeScanner
        if (scanner == null) { finishError("bluetooth_disabled", "بلوتوث گوشی را روشن کن."); return@begin }
        val uuid = ParcelUuid(UUID.fromString("0000FFF6-0000-1000-8000-00805F9B34FB"))
        val found = linkedMapOf<String, Map<String, Any>>()
        val callback = object : ScanCallback() {
            override fun onScanResult(type: Int, item: ScanResult) {
                if (generation != requestGeneration) return
                val bytes = item.scanRecord?.getServiceData(uuid) ?: return
                if (bytes.size < 3) return
                val discriminator = (bytes[1].toInt() and 255) or ((bytes[2].toInt() and 15) shl 8)
                found[item.device.address] = mapOf("id" to item.device.address,
                    "name" to (item.scanRecord?.deviceName ?: "وسیلهٔ Matter"),
                    "discriminator" to discriminator, "rssi" to item.rssi)
            }
            override fun onScanFailed(code: Int) {
                if (generation == requestGeneration) finishError("ble_scan_failed", "جست‌وجوی بلوتوث ناموفق بود؛ دوباره تلاش کن.")
            }
        }
        cleanup = { scanner.stopScan(callback) }
        scanner.startScan(listOf(ScanFilter.Builder().setServiceUuid(uuid).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
        handler.postDelayed({ finish(found.values.sortedByDescending { it["rssi"] as Int }) }, 8000)
    }

    fun nfc(result: MethodChannel.Result) = begin(result, emptyList()) {
        val requestGeneration = generation
        val adapter = NfcAdapter.getDefaultAdapter(activity)
        if (adapter == null || !adapter.isEnabled) {
            finishError("nfc_unavailable", "این گوشی NFC فعال ندارد؛ از QR استفاده کن."); return@begin
        }
        cleanup = { adapter.disableReaderMode(activity) }
        adapter.enableReaderMode(activity, { tag ->
            var ndef: Ndef? = null
            try {
                ndef = Ndef.get(tag)
                ndef?.connect()
                val message: NdefMessage? = ndef?.ndefMessage
                val payload = message?.records?.mapNotNull { record ->
                    if (record.tnf == NdefRecord.TNF_WELL_KNOWN && record.type.contentEquals(NdefRecord.RTD_TEXT)) {
                        val bytes = record.payload
                        if (bytes.isEmpty()) null else {
                            val start = 1 + (bytes[0].toInt() and 63)
                            if (start > bytes.size || (bytes[0].toInt() and 128) != 0) null
                            else String(bytes, start, bytes.size - start, Charsets.UTF_8)
                        }
                    } else record.toUri()?.toString()
                }?.firstOrNull { it.startsWith("MT:", ignoreCase = true) }
                handler.post {
                    if (generation != requestGeneration) return@post
                    if (payload == null) finishError("invalid_nfc", "این تگ کد اتصال Matter ندارد.")
                    else finish(payload.uppercase())
                }
            } catch (_: Exception) { handler.post {
                if (generation == requestGeneration) finishError("nfc_read_failed", "تگ خوانده نشد؛ دوباره نزدیک کن.")
            } }
            finally { try { ndef?.close() } catch (_: Exception) { } }
        }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V, null)
    }
}
