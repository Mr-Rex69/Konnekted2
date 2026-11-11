package com.mossapps.flick

import android.app.Application
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class CastPendingReplyTest {
    private class Reply : MethodChannel.Result {
        var successes = 0
        val errors = mutableListOf<String>()
        override fun success(result: Any?) { successes++ }
        override fun error(code: String, message: String?, details: Any?) { errors.add(code) }
        override fun notImplemented() { fail("Unexpected unsupported channel") }
    }

    @Test fun routeSelectionDoesNotCompleteAConnectionBeforeReceiverAcknowledgement() {
        val reply = Reply()
        val request = CastPendingReply(reply, Handler(Looper.getMainLooper()))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        assertEquals(0, reply.successes)
        request.succeed()
        request.succeed()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(30))
        assertEquals(1, reply.successes)
        assertTrue(reply.errors.isEmpty())
    }

    @Test fun timeoutAndLateReceiverCallbackProduceOneError() {
        val reply = Reply()
        var retired = 0
        val request = CastPendingReply(reply, Handler(Looper.getMainLooper()), onFinished = { retired++ })
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(21))
        request.succeed()
        assertEquals(listOf("CAST_TIMEOUT"), reply.errors)
        assertEquals(0, reply.successes)
        assertEquals(1, retired)
    }

    @Test fun failedLoadCannotBecomeSuccessThroughADelayedCallback() {
        val reply = Reply()
        val request = CastPendingReply(reply, Handler(Looper.getMainLooper()))
        request.fail("CAST_COMMAND", "Receiver rejected format")
        request.succeed()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(30))
        assertEquals(listOf("CAST_COMMAND"), reply.errors)
        assertEquals(0, reply.successes)
    }
}
