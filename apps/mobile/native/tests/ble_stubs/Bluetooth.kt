package android.bluetooth
import android.content.Context
import android.bluetooth.le.BluetoothLeScanner
import java.util.UUID
class BluetoothAdapter {
 var isEnabled = true
 val bluetoothLeScanner = BluetoothLeScanner()
 companion object { val instance = BluetoothAdapter(); fun getDefaultAdapter() = instance }
}
class BluetoothDevice {
 val address = "test"
 lateinit var callback: BluetoothGattCallback
 val gatt = BluetoothGatt()
 fun connectGatt(context: Context, auto: Boolean, cb: BluetoothGattCallback): BluetoothGatt {
  callback = cb; return gatt
 }
}
class BluetoothGatt {
 companion object { const val GATT_SUCCESS = 0 }
 fun discoverServices() = true
 fun requestMtu(mtu: Int) = true
 fun disconnect() {}
 fun close() {}
}
object BluetoothProfile { const val STATE_CONNECTED = 2; const val STATE_DISCONNECTED = 0 }
class BluetoothGattService(val uuid: UUID)
class BluetoothGattCharacteristic(val uuid: UUID, val service: BluetoothGattService) {
 var value: ByteArray? = null
}
class BluetoothGattDescriptor
open class BluetoothGattCallback {
 open fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {}
 open fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {}
 open fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {}
 open fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {}
 open fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {}
 open fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {}
 open fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {}
 open fun onDescriptorRead(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {}
 open fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {}
 open fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {}
 open fun onReliableWriteCompleted(gatt: BluetoothGatt, status: Int) {}
}
