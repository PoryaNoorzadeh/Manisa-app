package android.os
import java.util.UUID
class ParcelUuid(val uuid: UUID)
class Looper { companion object { fun getMainLooper() = Looper() } }
class Handler(looper: Looper) {
 companion object {
  val queue = ArrayDeque<Runnable>()
  fun drain() { while (queue.isNotEmpty()) queue.removeFirst().run() }
 }
 fun post(r: Runnable): Boolean { queue.add(r); return true }
 fun postDelayed(r: Runnable, delay: Long) = true
 fun removeCallbacks(r: Runnable) { queue.remove(r) }
}
