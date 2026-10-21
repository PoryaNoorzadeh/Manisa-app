package com.manisa.manisa_mobile

fun main() {
    // Timeout, scan failure, pairing exception and user cancel all share finish().
    for (terminal in listOf("timeout", "scan failure", "pairing failure", "cancel", "success")) {
        val gate = ManisaCommissioningGate<Any>()
        val failed = Any()
        check(gate.begin(failed))
        check(!gate.begin(Any())) // single-flight while native work is active
        check(gate.finish(failed, succeeded = terminal == "success")) { "$terminal must release the attempt" }
        check(gate.current == null)
        check(gate.lastSucceeded == (terminal == "success")) // cancellation must preserve an in-flight success reply
        val retry = Any()
        check(gate.begin(retry)) { "$terminal must allow immediate retry" }
        check(!gate.lastSucceeded) // a prior success cannot rescue a new cancelled attempt
        check(!gate.finish(failed, succeeded = true)) // delayed timer/discovery/native callback from prior attempt
        check(gate.current === retry)
        check(!gate.begin(Any())) // stale callback must not release retry's busy guard
        check(gate.finish(retry))
        check(!gate.finish(retry)) // MethodChannel result must settle once
    }
    val pendingPermission = ManisaCommissioningGate<Any>()
    val success = Any()
    check(pendingPermission.begin(success))
    check(pendingPermission.finish(success, succeeded = true))
    check(pendingPermission.lastSucceeded)
    pendingPermission.clearOutcome() // accepted new request may await permission before begin()
    check(!pendingPermission.lastSucceeded)
    println("Native commissioning ownership checks passed: retry, single-flight, stale callbacks, exactly-once finish")
}
