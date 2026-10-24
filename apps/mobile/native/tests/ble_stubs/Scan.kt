package android.bluetooth.le
import android.bluetooth.BluetoothDevice
import android.os.ParcelUuid
open class ScanCallback {
 open fun onScanResult(callbackType: Int, result: ScanResult) {}
 open fun onScanFailed(errorCode: Int) {}
}
class ScanResult(val device: BluetoothDevice)
class ScanFilter { class Builder {
 fun setServiceData(uuid: ParcelUuid, data: ByteArray, mask: ByteArray) = this
 fun build() = ScanFilter()
} }
class ScanSettings {
 companion object { const val SCAN_MODE_LOW_LATENCY = 2 }
 class Builder { fun setScanMode(mode: Int) = this; fun build() = ScanSettings() }
}
class BluetoothLeScanner {
 lateinit var callback: ScanCallback
 fun startScan(filters: List<ScanFilter>, settings: ScanSettings, cb: ScanCallback) { callback = cb }
 fun stopScan(cb: ScanCallback) {}
}
