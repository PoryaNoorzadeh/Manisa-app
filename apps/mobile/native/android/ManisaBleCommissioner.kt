package com.manisa.manisa_mobile

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import chip.platform.AndroidChipPlatform
import chip.platform.BleCallback
import java.util.UUID

/**
 * Minimal BLE rendezvous transport matching the path proven by the official Matter CHIPTool.
 *
 * The Matter controller still owns PASE/commissioning. This class only discovers the Matter
 * service by discriminator, establishes GATT, forwards Android BLE callbacks into the Matter
 * platform, and returns the CHIP BLE connection id.
 */
internal class ManisaBleCommissioner(
    private val context: Context,
    private val platform: AndroidChipPlatform,
) : BleCallback {
    companion object {
        private const val TAG = "ManisaMatterBle"
        private const val CHIP_UUID = "0000FFF6-0000-1000-8000-00805F9B34FB"
        private const val SCAN_TIMEOUT_MS = 15_000L
    }

    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private val handler = Handler(Looper.getMainLooper())

    private var scannerCallback: ScanCallback? = null
    private var bleGatt: BluetoothGatt? = null
    private var connectionId: Int = 0
    private var completedGattSetup = false
    private var onConnected: ((BluetoothGatt, Int) -> Unit)? = null
    private var onFailure: ((String) -> Unit)? = null

    fun start(
        discriminator: Int,
        isShortDiscriminator: Boolean,
        connected: (BluetoothGatt, Int) -> Unit,
        failed: (String) -> Unit,
    ) {
        cancelScan()
        completedGattSetup = false
        onConnected = connected
        onFailure = failed

        val adapter = bluetoothAdapter
        if (adapter == null) {
            fail("Bluetooth adapter is unavailable")
            return
        }
        if (!adapter.isEnabled) {
            fail("Bluetooth is disabled")
            return
        }
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            fail("Bluetooth LE scanner is unavailable")
            return
        }

        val serviceData = getServiceData(discriminator)
        val serviceDataMask = getServiceDataMask(isShortDiscriminator)
        val filter = ScanFilter.Builder()
            .setServiceData(
                ParcelUuid(UUID.fromString(CHIP_UUID)),
                serviceData,
                serviceDataMask,
            )
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                Log.i(TAG, "Matter BLE device discovered: ${result.device.address}")
                cancelScan()
                connect(result.device)
            }

            override fun onScanFailed(errorCode: Int) {
                fail("Matter BLE scan failed (error $errorCode)")
            }
        }
        scannerCallback = callback
        Log.i(
            TAG,
            "Starting Matter BLE scan discriminator=$discriminator short=$isShortDiscriminator",
        )
        scanner.startScan(listOf(filter), settings, callback)
        handler.postDelayed(
            {
                if (scannerCallback != null) {
                    fail("Matter device was not found over Bluetooth")
                }
            },
            SCAN_TIMEOUT_MS,
        )
    }

    fun cancel() {
        cancelScan()
        if (!completedGattSetup) {
            bleGatt?.disconnect()
            bleGatt?.close()
            bleGatt = null
        }
        onConnected = null
        onFailure = null
    }

    private fun connect(device: BluetoothDevice) {
        val callback = createGattCallback()
        Log.i(TAG, "Connecting to Matter BLE device ${device.address}")
        val gatt = device.connectGatt(context, false, callback)
        bleGatt = gatt
        connectionId = platform.bleManager.addConnection(gatt)
        platform.bleManager.setBleCallback(this)
        if (connectionId == 0) {
            fail("Matter BLE connection registration failed")
        }
    }

    private fun createGattCallback(): BluetoothGattCallback {
        val wrappedCallback = platform.bleManager.callback
        return object : BluetoothGattCallback() {
            private var state = 1

            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                super.onConnectionStateChange(gatt, status, newState)
                wrappedCallback.onConnectionStateChange(gatt, status, newState)
                Log.i(TAG, "BLE state status=$status newState=$newState")

                if (newState == BluetoothProfile.STATE_CONNECTED &&
                    status == BluetoothGatt.GATT_SUCCESS
                ) {
                    state = 2
                    gatt?.discoverServices()
                } else if (!completedGattSetup && newState == BluetoothProfile.STATE_DISCONNECTED) {
                    fail("Matter BLE connection closed before commissioning started (status $status)")
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                wrappedCallback.onServicesDiscovered(gatt, status)
                Log.i(TAG, "BLE services discovered status=$status")
                if (state != 2 || status != BluetoothGatt.GATT_SUCCESS) {
                    fail("Matter BLE service discovery failed (status $status)")
                    return
                }
                state = 3
                if (gatt?.requestMtu(247) != true) {
                    fail("Matter BLE MTU request could not be started")
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
                super.onMtuChanged(gatt, mtu, status)
                wrappedCallback.onMtuChanged(gatt, mtu, status)
                Log.i(TAG, "BLE MTU changed mtu=$mtu status=$status")
                if (state != 3 || gatt == null || status != BluetoothGatt.GATT_SUCCESS) {
                    fail("Matter BLE MTU negotiation failed (status $status)")
                    return
                }
                completedGattSetup = true
                onConnected?.invoke(gatt, connectionId)
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                wrappedCallback.onCharacteristicChanged(gatt, characteristic)
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                wrappedCallback.onCharacteristicRead(gatt, characteristic, status)
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                wrappedCallback.onCharacteristicWrite(gatt, characteristic, status)
            }

            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                wrappedCallback.onDescriptorRead(gatt, descriptor, status)
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                wrappedCallback.onDescriptorWrite(gatt, descriptor, status)
            }

            override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
                wrappedCallback.onReadRemoteRssi(gatt, rssi, status)
            }

            override fun onReliableWriteCompleted(gatt: BluetoothGatt, status: Int) {
                wrappedCallback.onReliableWriteCompleted(gatt, status)
            }
        }
    }

    private fun cancelScan() {
        val callback = scannerCallback ?: return
        try {
            bluetoothAdapter?.bluetoothLeScanner?.stopScan(callback)
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to stop BLE scan", error)
        }
        scannerCallback = null
    }

    private fun fail(message: String) {
        Log.e(TAG, message)
        cancelScan()
        if (!completedGattSetup) {
            bleGatt?.disconnect()
            bleGatt?.close()
            bleGatt = null
        }
        val callback = onFailure
        onConnected = null
        onFailure = null
        callback?.invoke(message)
    }

    private fun getServiceData(discriminator: Int): ByteArray {
        val opcode = 0
        val version = 0
        val versionDiscriminator = ((version and 0xf) shl 12) or (discriminator and 0xfff)
        return intArrayOf(opcode, versionDiscriminator, versionDiscriminator shr 8)
            .map { it.toByte() }
            .toByteArray()
    }

    private fun getServiceDataMask(isShortDiscriminator: Boolean): ByteArray {
        val shortDiscriminatorMask = if (isShortDiscriminator) 0x00 else 0xff
        return intArrayOf(0xff, shortDiscriminatorMask, 0xff)
            .map { it.toByte() }
            .toByteArray()
    }

    override fun onCloseBleComplete(connId: Int) {
        Log.i(TAG, "Matter BLE close complete connId=$connId")
        connectionId = 0
    }

    override fun onNotifyChipConnectionClosed(connId: Int) {
        Log.i(TAG, "Matter requested BLE connection close connId=$connId")
        bleGatt?.close()
        bleGatt = null
        connectionId = 0
    }
}
