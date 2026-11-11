package com.mossapps.flick

import android.os.Handler
import io.flutter.plugin.common.MethodChannel

/** A native Cast acknowledgement owns the channel reply, never route selection. */
internal class CastPendingReply(
    private val result: MethodChannel.Result,
    private val handler: Handler,
    private val onFinished: () -> Unit = {},
    private val onTimeout: () -> Unit = {},
    timeoutMs: Long = 20_000,
) {
    private var finished = false
    private val timeout = Runnable {
        if (!finished) {
            fail("CAST_TIMEOUT", "The Cast receiver did not confirm the operation.")
            onTimeout()
        }
    }
    init { handler.postDelayed(timeout, timeoutMs) }
    fun succeed() = finish { result.success(null) }
    fun fail(code: String, message: String) = finish { result.error(code, message, null) }
    private fun finish(reply: () -> Unit) {
        if (finished) return
        finished = true
        handler.removeCallbacks(timeout)
        onFinished()
        reply()
    }
}
