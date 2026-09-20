package com.manisa.manisa_mobile

fun main() {
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
