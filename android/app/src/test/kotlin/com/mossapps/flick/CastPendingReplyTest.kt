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

    @Test fun receiverGetsConcreteTypePausedStartAndMillisecondPosition() {
        val load = castMediaLoad("http://192.0.2.1:5000/token/track.flac", "Track", "Artist", "audio/flac", false, 17250)
        assertEquals("audio/flac", load.mediaInfo!!.contentType)
        assertEquals(false, load.autoplay)
        assertEquals(17250L, load.currentTime)
    }

    @Test fun artworkAndIdentityReachTheBrandedReceiver() {
        val load = castMediaLoad("http://192.0.2.1/track.flac", "Track", "Artist", "audio/flac", false, 0,
            "Album", "http://192.0.2.1/cover.jpg", "recording", "load-2")
        val info = load.mediaInfo!!
        assertEquals("Album", info.metadata!!.getString(com.google.android.gms.cast.MediaMetadata.KEY_ALBUM_TITLE))
        assertEquals("http://192.0.2.1/cover.jpg", info.metadata!!.images.first().url.toString())
        assertEquals("recording", info.customData!!.getString("trackId"))
        assertEquals("load-2", info.customData!!.getString("loadId"))
    }

    @Test fun terminalStatusRetainsIdentityButAnotherSendersMediaClearsIt() {
        val identity = CastMediaIdentity()
        val mobile = castMediaLoad("http://192.0.2.1/mobile.flac", null, null, "audio/flac", true, 0,
            trackId = "mobile-track", loadId = "mobile-load").mediaInfo
        identity.update(mobile)
        identity.update(null) // CAF terminal status may omit media information.
        assertEquals("mobile-load", identity.loadId)
        assertEquals("mobile-track", identity.trackId)
        val replacement = castMediaLoad("http://192.0.2.1/desktop.flac", null, null, "audio/flac", true, 0).mediaInfo
        identity.update(replacement)
        identity.update(null)
        assertNull(identity.loadId)
        assertNull(identity.trackId)
        identity.update(mobile)
        identity.clear()
        assertNull(identity.loadId)
    }

    @Test fun contentGrantIsNeverSentAsAReceiverUrl() {
        try {
            castMediaLoad("content://library/track", null, null, "audio/flac", true, 0)
            fail("SAF grants must be served through HTTP")
        } catch (_: IllegalArgumentException) { }
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
