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

/** Power Source (0x002F) attributes: percentages retain half-percent units. */
object ManisaPowerCodec {
    val attributes = mapOf(0xFFFCL to "features", 0L to "status", 12L to "percent",
        14L to "chargeLevel", 15L to "replacementNeeded", 26L to "chargeState", 9L to "wiredPresent")
    fun decode(attribute: Long, raw: Any?): Pair<String, Any?>? {
        val name = attributes[attribute] ?: return null
        if (attribute == 15L || attribute == 9L) {
            require(raw is Boolean) { "Invalid power source flag" }
        } else if (attribute == 12L && raw == null) {
            return name to null
        } else {
            val maximum = when (attribute) { 0xFFFCL -> 0xffffffffL; 12L -> 200L; else -> 255L }
            require(raw is Long && raw in 0..maximum) { "Invalid power source number" }
        }
        return name to raw
    }
}
