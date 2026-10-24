package chip.platform
import android.bluetooth.*
interface BleCallback {
 fun onCloseBleComplete(connId: Int)
 fun onNotifyChipConnectionClosed(connId: Int)
}
class AndroidChipPlatform {
 val received = mutableListOf<ByteArray>()
 val bleManager = TestBleManager(this)
 fun handleIndicationReceived(id: Int, service: ByteArray, characteristic: ByteArray, value: ByteArray) {
  received.add(value.copyOf())
 }
}
class TestBleManager(val platform: AndroidChipPlatform) {
 private var connection: BluetoothGatt? = null
 fun addConnection(gatt: BluetoothGatt): Int { connection = gatt; return 1 }
 fun getConnection(id: Int) = connection
 fun removeConnection(id: Int) { connection = null }
 fun setBleCallback(cb: BleCallback) {}
 val callback = object : BluetoothGattCallback() {
  override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
   // The official v1.5.1.0 manager reads this mutable value at delivery time.
   platform.handleIndicationReceived(1, byteArrayOf(), byteArrayOf(), characteristic.value!!)
  }
 }
}
