package com.mossapps.flick

import android.app.Application
import android.app.Notification
import android.content.Intent
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import androidx.media.app.NotificationCompat as MediaNotificationCompat
import androidx.mediarouter.media.MediaRouter
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.android.controller.ServiceController

/** Verify notification/session-token publication without requiring an Activity. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class MusicMediaSessionTest {
    private lateinit var lifecycle: ServiceController<MusicNotificationService>
    private lateinit var service: MusicNotificationService

    @Before fun create() {
        lifecycle = Robolectric.buildService(MusicNotificationService::class.java).create()
        service = lifecycle.get()
    }

    @After fun destroy() { lifecycle.destroy() }

    private fun playLocally() {
        service.onStartCommand(Intent().apply {
            putExtra("title", "PC library recording")
            putExtra("artist", "Artist")
            putExtra("duration", 240000L)
            putExtra("position", 12000L)
            putExtra("isPlaying", true)
            putExtra("isCasting", false)
            putExtra("isRemotePlayback", false)
        }, 0, 1)
    }

    @Test fun startupNotificationAlreadyCarriesTheSystemSession() {
        val method = MusicNotificationService::class.java.getDeclaredMethod("buildStartupNotification")
        method.isAccessible = true
        val notification = method.invoke(service) as Notification
        assertEquals(service.sessionToken, MediaNotificationCompat.MediaStyle.getMediaSession(notification))
        assertEquals(Notification.CATEGORY_TRANSPORT, notification.category)
    }

    @Test fun localPcRecordingPublishesForegroundMediaWithoutAnActivity() {
        playLocally()
        assertEquals(service.sessionToken, MediaRouter.getInstance(service).mediaSessionToken)
        val foreground = requireNotNull(shadowOf(service).lastForegroundNotification)
        assertEquals("PC library recording", foreground.extras.getCharSequence(Notification.EXTRA_TITLE))
        assertEquals(service.sessionToken, MediaNotificationCompat.MediaStyle.getMediaSession(foreground))
    }

    @Test fun foregroundUpdatesKeepTheLatestMediaNotification() {
        playLocally()
        service.onStartCommand(Intent().apply {
            putExtra("title", "Next recording")
            putExtra("isPlaying", false)
        }, 0, 2)
        val foreground = requireNotNull(shadowOf(service).lastForegroundNotification)
        assertEquals("Next recording", foreground.extras.getCharSequence(Notification.EXTRA_TITLE))
        assertEquals(service.sessionToken, MediaNotificationCompat.MediaStyle.getMediaSession(foreground))
    }

    @Test fun returningFromPcControlRestoresTheSameLocalSessionAndRouteAssociation() {
        service.onStartCommand(Intent().apply {
            putExtra("title", "PC output")
            putExtra("isPlaying", true)
            putExtra("isRemotePlayback", true)
        }, 0, 1)
        assertNotEquals(service.sessionToken, MediaRouter.getInstance(service).mediaSessionToken)
        playLocally()
        assertEquals(service.sessionToken, MediaRouter.getInstance(service).mediaSessionToken)
    }

    private fun startingCar(channel: MethodChannel?) {
        MusicNotificationService::class.java.getDeclaredField("carEngineStarting").apply {
            isAccessible = true; setBoolean(service, true)
        }
        setPlayerChannel(channel)
    }

    private fun setPlayerChannel(channel: MethodChannel?) {
        MusicNotificationService::class.java.getDeclaredField("methodChannel").apply {
            isAccessible = true; set(service, channel)
        }
    }

    private fun command(name: String, args: Map<String, Any>? = null) {
        MusicNotificationService::class.java.getDeclaredMethod(
            "sendCommandToFlutter", String::class.java, Map::class.java
        ).apply { isAccessible = true }.invoke(service, name, args)
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun ready() {
        MusicNotificationService::class.java.getDeclaredMethod("finishCarEngineStartup")
            .apply { isAccessible = true }.invoke(service)
    }

    private fun recordingChannel(calls: MutableList<String>): MethodChannel {
        val messenger = Proxy.newProxyInstance(
            BinaryMessenger::class.java.classLoader, arrayOf(BinaryMessenger::class.java)
        ) { _, method, args ->
            if (method.name == "send") {
                val message = (args!![1] as ByteBuffer).duplicate().apply { flip() }
                calls.add(StandardMethodCodec.INSTANCE.decodeMethodCall(message).method)
            }
            null
        } as BinaryMessenger
        return MethodChannel(messenger, "com.mossapps.flick/player")
    }

    @Test fun carPlayWaitsForDartInsteadOfBeingDroppedDuringStartup() {
        val calls = mutableListOf<String>()
        startingCar(null)
        command("play")
        assertTrue(calls.isEmpty())
        setPlayerChannel(recordingChannel(calls))
        ready()
        assertEquals(listOf("play"), calls)
        ready()
        assertEquals(listOf("play"), calls)
    }

    @Test fun pauseAndStopFollowPlayWhenCarConnectsBeforeDartIsReady() {
        val calls = mutableListOf<String>()
        startingCar(recordingChannel(calls))
        command("play")
        command("pause")
        command("stop")
        assertTrue(calls.isEmpty())
        ready()
        assertEquals(listOf("play", "pause", "stop"), calls)
        command("play")
        assertEquals(listOf("play", "pause", "stop", "play"), calls)
    }

}
