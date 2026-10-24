"""Run actual Activity callbacks against a non-reentrant JNI boundary.

Only Android scheduling and the hardware-facing controller are doubled. Extract
the production methods verbatim so an inline callback regression fails this test.
The real Android bridge is also compiled by the integrated APK workflow.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'android/MainActivityBle.kt').read_text()


def method(name):
    start = source.index('    private fun ' + name + '(')
    end = source.index('\n    private fun ', start + 1)
    return source[start:end]


harness = r'''
package com.manisa.manisa_mobile

object Log {
    fun i(tag: String, message: String) {}
    fun w(tag: String, message: String, error: Throwable?) {}
}
object MethodChannel {
    interface Result {
        fun success(result: Any?)
        fun error(code: String, message: String?, details: Any?)
        fun notImplemented()
    }
}
class RecordingResult : MethodChannel.Result {
    val replies = mutableListOf<Any?>()
    override fun success(result: Any?) { replies.add(result) }
    override fun error(code: String, message: String?, details: Any?) { replies.add(code) }
    override fun notImplemented() { error("notImplemented", null, null) }
}
open class GenericChipDeviceListener {
    open fun onPairingComplete(code: Long) {}
    open fun onCommissioningStatusUpdate(nodeId: Long, stage: String, errorCode: Long) {}
    open fun onCommissioningComplete(nodeId: Long, errorCode: Long) {}
    open fun onError(error: Throwable?) {}
}
class Queue {
    val tasks = ArrayDeque<Runnable>()
    fun post(task: Runnable): Boolean { tasks.add(task); return true }
    fun postDelayed(task: Runnable, delay: Long) = true
    fun removeCallbacks(task: Runnable) { tasks.remove(task) }
    fun drain() { while (tasks.isNotEmpty()) tasks.removeFirst().run() }
}
class NativeController {
    var stackLocked = false
    var continued = 0
    var stopped = 0
    var attestation: (Long, Any?, Long) -> Unit = { _, _, _ -> }
    fun nativeEntry() {
        // Assert instead of actually deadlocking the test process.
        if (stackLocked) throw AssertionError("JNI re-entry while Matter StackLock is held")
    }
    fun callback(body: () -> Unit) {
        stackLocked = true
        try { body() } finally { stackLocked = false }
    }
    fun setDeviceAttestationDelegate(timeout: Int, cb: (Long, Any?, Long) -> Unit) { attestation = cb }
    fun getDeviceBeingCommissionedPointer(nodeId: Long): Long { nativeEntry(); return 123L }
    fun continueCommissioning(pointer: Long, ignore: Boolean) {
        nativeEntry(); check(pointer == 123L); continued++
    }
    fun setCompletionListener(listener: GenericChipDeviceListener) {}
    fun stopDevicePairing(nodeId: Long) { nativeEntry(); stopped++ }
    fun close() {}
}
class Ble { fun cancel() {} }
class Harness {
    val controller = NativeController()
    val sensorHandler = Queue()
    val commissionGate = ManisaCommissioningGate<CommissionAttempt>()
    val pendingCommission get() = commissionGate.current
    var bleCommissioner: Ble? = null
    val TAG = "test"
    val STATUS_OK = 0L
    val DEVICE_ATTESTATION_TIMEOUT = 600
    class CommissionAttempt(val nodeId: Long, val result: MethodChannel.Result) {
        var commissioned = false
        var timeout: Runnable? = null
    }
    // Android Activity.runOnUiThread runs inline when called on the UI thread.
    fun runOnUiThread(action: () -> Unit) = action()
    fun discoverOnOffEndpoints(nodeId: Long, result: MethodChannel.Result, subscribe: Boolean) {
        controller.nativeEntry()
        result.success(listOf(1))
    }
    fun begin(): Pair<CommissionAttempt, RecordingResult> {
        val result = RecordingResult()
        val attempt = CommissionAttempt(42, result)
        check(commissionGate.begin(attempt))
        bindAttestationDelegate(attempt)
        return attempt to result
    }
    fun listener(attempt: CommissionAttempt) = commissioningListener(attempt)
    fun cancel(attempt: CommissionAttempt) = failPendingCommission(attempt, "cancelled", "cancelled", null)
    // PRODUCTION_METHODS
}
fun main() {
    val failures = mutableListOf<String>()
    fun case(name: String, test: () -> Unit) {
        try { test() } catch (error: Throwable) { failures.add("$name: ${error.message}") }
    }
    case("attestation delivered synchronously under JNI lock") {
        val h = Harness(); h.begin()
        h.controller.callback { h.controller.attestation(123, null, 0) }
        h.sensorHandler.drain()
        check(h.controller.continued == 1)
    }
    case("completion discovery waits for JNI callback to return") {
        val h = Harness(); val (attempt, result) = h.begin()
        h.controller.callback { h.listener(attempt).onCommissioningComplete(42, 0) }
        h.sensorHandler.drain()
        check(result.replies.single() is Map<*, *>)
    }
    case("failed completion cleanup waits for JNI callback to return") {
        val h = Harness(); val (attempt, result) = h.begin()
        h.controller.callback { h.listener(attempt).onCommissioningComplete(42, 5) }
        h.sensorHandler.drain()
        check(result.replies.single() == "commissioning_failed")
        check(h.controller.stopped == 1)
    }
    case("cancel before queued attestation prevents stale pointer use") {
        val h = Harness(); val (attempt, _) = h.begin()
        h.controller.callback { h.controller.attestation(123, null, 0) }
        h.cancel(attempt)
        h.begin()
        h.sensorHandler.drain()
        check(h.controller.continued == 0)
    }
    check(failures.isEmpty()) { failures.joinToString("\n") }
    println("4 commissioning JNI re-entry regression checks passed")
}
'''
methods = '\n'.join(method(name) for name in (
    'bindAttestationDelegate', 'commissioningListener', 'releaseCommission',
    'completeCommission', 'failPendingCommission',
))
with tempfile.TemporaryDirectory() as folder:
    folder = Path(folder)
    kt = folder / 'CommissioningReentrancyTest.kt'
    kt.write_text(harness.replace('// PRODUCTION_METHODS', methods))
    jar = folder / 'test.jar'
    subprocess.run([os.environ.get('KOTLINC', 'kotlinc'), '-nowarn', str(kt),
                    str(ROOT / 'android/ManisaCommissioningGate.kt'),
                    '-include-runtime', '-d', str(jar)], check=True)
    subprocess.run(['java', '-jar', str(jar)], check=True)
