package com.manisa.manisa_mobile

import android.bluetooth.*
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Handler
import chip.devicecontroller.ChipDeviceController
import chip.platform.AndroidChipPlatform
import java.util.UUID

fun main() {
    val errors = mutableListOf<String>()
    var checks = 0
    fun runCase(name: String, body: (ManisaBleCommissioner, BluetoothDevice, AndroidChipPlatform, MutableList<String>) -> Unit) {
        val platform = AndroidChipPlatform()
        val failures = mutableListOf<String>()
        val commissioner = ManisaBleCommissioner(Context(), platform, ChipDeviceController())
        commissioner.start(1234, false, { _, _ -> }, { failures.add(it) })
        val device = BluetoothDevice()
        BluetoothAdapter.instance.bluetoothLeScanner.callback.onScanResult(0, ScanResult(device))
        Handler.drain()
        try { body(commissioner, device, platform, failures); checks++ }
        catch (e: Throwable) { errors.add("$name: ${e.message}") }
        commissioner.cancel()
        Handler.drain()
    }
    fun characteristic() = BluetoothGattCharacteristic(UUID.fromString("18ee2ef5-263d-4559-959f-4f9c429f9d11"),
        BluetoothGattService(UUID.fromString("0000fff6-0000-1000-8000-00805f9b34fb")))
    runCase("legacy indications retain distinct packet bytes") { _, d, p, _ ->
        val c = characteristic()
        val first = byteArrayOf(1, 2)
        c.value = first
        d.callback.onCharacteristicChanged(d.gatt, c)
        first[0] = 99
        c.value = byteArrayOf(3, 4)
        d.callback.onCharacteristicChanged(d.gatt, c)
        Handler.drain()
        check(p.received.map { it.toList() } == listOf(listOf<Byte>(1, 2), listOf<Byte>(3, 4))) { "packets were overwritten: ${p.received.map { it.toList() }}" }
    }
    runCase("Android 13 callback uses supplied bytes") { _, d, p, _ ->
        val c = characteristic()
        c.value = byteArrayOf(99)
        val value = byteArrayOf(5, 6)
        d.callback.onCharacteristicChanged(d.gatt, c, value)
        value[0] = 88
        Handler.drain()
        check(p.received.single().contentEquals(byteArrayOf(5, 6)))
    }
    runCase("null payload fails before JNI") { _, d, p, failures ->
        d.callback.onCharacteristicChanged(d.gatt, characteristic())
        Handler.drain()
        check(p.received.isEmpty())
        check(failures.single() == "Matter BLE indication had no payload") { "null was not rejected before native delivery: $failures" }
    }
    runCase("failure stops native pairing before removing GATT") { c, d, p, _ ->
        c.cancel()
        var connectionPresentOnFailure = false
        c.start(1234, false, { _, _ -> }, {
            connectionPresentOnFailure = p.bleManager.getConnection(1) != null
        })
        BluetoothAdapter.instance.bluetoothLeScanner.callback.onScanResult(0, ScanResult(d))
        Handler.drain()
        d.callback.onServicesDiscovered(d.gatt, 0)
        d.callback.onConnectionStateChange(d.gatt, 0, BluetoothProfile.STATE_CONNECTED)
        Handler.drain()
        d.callback.onServicesDiscovered(d.gatt, 1)
        Handler.drain()
        check(connectionPresentOnFailure) { "GATT removed before owner could stop native pairing" }
        check(p.bleManager.getConnection(1) == null)
    }
    runCase("cancel drops queued packets") { c, d, p, _ ->
        val characteristic = characteristic().also { it.value = byteArrayOf(1) }
        d.callback.onCharacteristicChanged(d.gatt, characteristic)
        c.cancel()
        Handler.drain()
        check(p.received.isEmpty())
    }
    check(errors.isEmpty()) { errors.joinToString("\n") }
    println("$checks BLE transport regression checks passed")
}
