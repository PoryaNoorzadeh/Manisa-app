package com.manisa.manisa_mobile

/** Wire policy shared by Android TLV decoding and the host regression runner. */
object ManisaSensorCodec {
    const val CONTACT_DEVICE_TYPE = 0x0015L

    // null result means unsupported. A pair whose value is null means an
    // environmental attribute is supported but the device has no measurement.
    fun decode(cluster: Long, raw: Any?, deviceTypes: Set<Long> = emptySet()): Pair<String, Any?>? {
        return when (cluster) {
            0x0402L -> {
                require(raw == null || raw is Int && raw in -27315..32767) { "Invalid temperature" }
                "temperature" to raw
            }
            0x0405L -> {
                require(raw == null || raw is Int && raw in 0..10000) { "Invalid humidity" }
                "humidity" to raw
            }
            0x0406L -> {
                require(raw is Int && raw in 0..1) { "Invalid occupancy bitmap" }
                "occupancy" to ((raw and 1) != 0)
            }
            0x0045L -> {
                if (CONTACT_DEVICE_TYPE !in deviceTypes) return null
                require(raw is Boolean) { "Invalid contact state" }
                "contactClosed" to raw
            }
            else -> null
        }
    }
}
