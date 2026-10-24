# BLE transport test doubles

These minimal Android/CHIP doubles run the **production ManisaBleCommissioner** on the JVM without a phone. The Handler deliberately delays callbacks so tests can mutate Android's reused characteristic/value before delivery. The legacy SDK double reads characteristic.value exactly as AndroidBleManager v1.5.1.0 does.

They test packet ownership, Android 13 callback selection, null rejection, cancellation and cleanup ordering. They do not prove native ABI compatibility, radio behavior, commissioning success, or absence of native crashes. The APK workflow separately compiles against the real Android and Matter SDKs. Physical-device acceptance remains required.

Sources: project-chip/connectedhomeip tag v1.5.1.0, src/platform/android/java/chip/platform/AndroidBleManager.java and src/platform/android/AndroidChipPlatform-JNI.cpp.
