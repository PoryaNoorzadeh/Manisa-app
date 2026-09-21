package com.manisa.manisa_mobile

fun main() {
    check(ManisaPowerCodec.decode(12L, 0L) == ("percent" to 0L))
    check(ManisaPowerCodec.decode(12L, 199L) == ("percent" to 199L))
    check(ManisaPowerCodec.decode(12L, 200L) == ("percent" to 200L))
    check(ManisaPowerCodec.decode(12L, null) == ("percent" to null))
    check(ManisaPowerCodec.decode(15L, false) == ("replacementNeeded" to false))
    check(ManisaPowerCodec.decode(0xFFFCL, 0xffffffffL) == ("features" to 0xffffffffL))
    check(ManisaPowerCodec.decode(14L, 255L) == ("chargeLevel" to 255L))
    for ((attribute, raw) in listOf(12L to 201L, 12L to -1L, 15L to 0L,
        0L to null, 0xFFFCL to 0x100000000L, 12L to "100")) {
        check(runCatching { ManisaPowerCodec.decode(attribute, raw) }.isFailure)
    }
    val contact = setOf(ManisaSensorCodec.CONTACT_DEVICE_TYPE)
    fun rejects(block: () -> Unit) {
        check(runCatching(block).exceptionOrNull() is IllegalArgumentException)
    }
    check(ManisaSensorCodec.decode(0x0402L, -125) == ("temperature" to -125))
    check(ManisaSensorCodec.decode(0x0402L, -27315) == ("temperature" to -27315))
    check(ManisaSensorCodec.decode(0x0402L, 32767) == ("temperature" to 32767))
    check(ManisaSensorCodec.decode(0x0405L, 0) == ("humidity" to 0))
    check(ManisaSensorCodec.decode(0x0405L, 10000) == ("humidity" to 10000))
    check(ManisaSensorCodec.decode(0x0405L, null) == ("humidity" to null))
    rejects { ManisaSensorCodec.decode(0x0402L, -32768) }
    rejects { ManisaSensorCodec.decode(0x0405L, 10001) }
    check(ManisaSensorCodec.decode(0x0406L, 0) == ("occupancy" to false))
    check(ManisaSensorCodec.decode(0x0406L, 1) == ("occupancy" to true))
    for (invalid in listOf(null, 2, 255, -1, true, "1")) {
        rejects { ManisaSensorCodec.decode(0x0406L, invalid) }
    }
    check(ManisaSensorCodec.decode(0x0045L, true, contact) == ("contactClosed" to true))
    check(ManisaSensorCodec.decode(0x0045L, false, contact) == ("contactClosed" to false))
    check(ManisaSensorCodec.decode(0x0045L, true) == null)
    check(ManisaSensorCodec.decode(0x0045L, false, setOf(0x0043L)) == null)
    check(ManisaSensorCodec.decode(0x0045L, true, contact + 0x0302L) == ("contactClosed" to true))
    for (invalid in listOf(null, 0, 1, "false")) {
        rejects { ManisaSensorCodec.decode(0x0045L, invalid, contact) }
    }
    check(ManisaSensorCodec.decode(0x9999L, true, contact) == null)
    println("Native sensor policy checks passed: descriptor gating, boolean semantics, ranges and unknown values")
}
