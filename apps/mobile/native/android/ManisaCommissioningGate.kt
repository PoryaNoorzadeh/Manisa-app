package com.manisa.manisa_mobile

/** Main-thread ownership of one commissioning attempt. Old callbacks cannot finish a retry. */
class ManisaCommissioningGate<T : Any> {
    @Volatile var current: T? = null
        private set

    // A success reply can still be in flight after ownership is released. Cancellation
    // must report it so Flutter preserves the resulting device record.
    var lastSucceeded = false
        private set

    fun clearOutcome() { lastSucceeded = false }

    fun begin(attempt: T): Boolean {
        if (current != null) return false
        current = attempt
        clearOutcome()
        return true
    }

    fun finish(attempt: T, succeeded: Boolean = false): Boolean {
        if (current !== attempt) return false
        current = null
        lastSucceeded = succeeded
        return true
    }
}
