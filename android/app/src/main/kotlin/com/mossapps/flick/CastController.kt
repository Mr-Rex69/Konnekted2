package com.mossapps.flick

import android.content.Context
import android.util.Log
import android.os.Handler
import android.os.Looper
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.api.PendingResult
import io.flutter.plugin.common.MethodChannel

// ponytail: Cast driven via MediaRouter route selection + CastContext session.
// Discovery = MediaRouter routes supporting remote playback; connect = selectRoute
// (CastContext creates the session); control = RemoteMediaClient on the session.
// All interesting native state (session lifecycle, playback status, volume,
// route changes) is forwarded to Dart via onEvent → cast_events channel.
class CastController(private val context: Context) {
    private val mediaRouter: MediaRouter by lazy { MediaRouter.getInstance(context) }
    // ponytail: Cast SDK needs Google Play Services; null out on GMS-free
    // devices (GrapheneOS etc.) so the app runs without Cast instead of
    // crashing on launch. MediaRouter output routing still works without GMS.
    private val castContext: CastContext? by lazy {
        try {
            CastContext.getSharedInstance(context)
        } catch (e: Throwable) {
            Log.w("CastController", "Cast SDK unavailable (no Google Play Services): ${e.message}")
            null
        }
    }
    private val handler = Handler(Looper.getMainLooper())

    /** Called on the main thread for every cast event destined for Dart. */
    var onEvent: ((Map<String, Any?>) -> Unit)? = null

    private var connectedSession: CastSession? = null
    private var mediaClientCallback: RemoteMediaClient.Callback? = null
    private var attachedClient: RemoteMediaClient? = null
    private var lastVolume: Double? = null
    private var statusTicker: Runnable? = null

    private var pendingConnect: CastPendingReply? = null
    private var pendingDisconnect: CastPendingReply? = null
    private var pendingRouteId: String? = null
    private var disconnectRequested = false
    private var connectionMayBeStarting = false
    private val mediaReplies = mutableSetOf<CastPendingReply>()

    private fun sessionReady(session: CastSession, event: String) {
        if (disconnectRequested) {
            castContext?.sessionManager?.endCurrentSession(true)
            return
        }
        if (pendingRouteId != null && mediaRouter.selectedRoute.id != pendingRouteId) return
        connectedSession = session
        connectionMayBeStarting = false
        attachMediaClientListener(session)
        pendingConnect?.succeed()
        emit(mapOf("event" to event))
    }

    private fun sessionFailed(code: Int) {
        connectionMayBeStarting = false
        pendingConnect?.fail("CAST_CONNECT", "The receiver could not start a Cast session (status $code).")
        if (disconnectRequested) pendingDisconnect?.succeed()
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) = sessionReady(session, "sessionStarted")
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) = sessionReady(session, "sessionResumed")
        override fun onSessionEnded(session: CastSession, error: Int) {
            if (connectedSession != null && connectedSession !== session) return
            connectedSession = null
            connectionMayBeStarting = false
            detachMediaClientListener()
            failMediaReplies()
            pendingConnect?.fail("CAST_ENDED", "The Cast session ended before it was ready.")
            val confirmed = error == 0
            if (disconnectRequested) {
                if (confirmed) pendingDisconnect?.succeed()
                else pendingDisconnect?.fail("CAST_DISCONNECT", "Receiver shutdown was not confirmed (status $error).")
            }
            emit(mapOf("event" to "sessionEnded", "shutdownConfirmed" to confirmed))
        }
        override fun onSessionStarting(p0: CastSession) {}
        override fun onSessionStartFailed(p0: CastSession, p1: Int) = sessionFailed(p1)
        override fun onSessionEnding(p0: CastSession) {}
        override fun onSessionResuming(p0: CastSession, p1: String) {}
        override fun onSessionResumeFailed(p0: CastSession, p1: Int) = sessionFailed(p1)
        override fun onSessionSuspended(session: CastSession, reason: Int) {
            if (connectedSession !== session) return
            detachMediaClientListener()
            failMediaReplies()
            emit(mapOf("event" to "sessionEnded", "shutdownConfirmed" to false))
        }
    }

    private val routerCallback = object : MediaRouter.Callback() {
        override fun onRouteSelected(router: MediaRouter, route: MediaRouter.RouteInfo) {
            if (route.playbackType == MediaRouter.RouteInfo.PLAYBACK_TYPE_REMOTE) {
                emit(
                    mapOf(
                        "event" to "routeSelected",
                        "id" to route.id.toString(),
                        "name" to (route.name?.toString() ?: ""),
                    )
                )
            }
        }
        override fun onRouteUnselected(router: MediaRouter, route: MediaRouter.RouteInfo) {
            if (route.playbackType == MediaRouter.RouteInfo.PLAYBACK_TYPE_REMOTE) {
                emit(
                    mapOf(
                        "event" to "routeUnselected",
                        "id" to route.id.toString(),
                        "name" to (route.name?.toString() ?: ""),
                    )
                )
            }
        }
        override fun onRouteVolumeChanged(router: MediaRouter, route: MediaRouter.RouteInfo) {
            if (route.playbackType == MediaRouter.RouteInfo.PLAYBACK_TYPE_REMOTE && route.volumeMax > 0) {
                emit(
                    mapOf(
                        "event" to "volume",
                        "volume" to route.volume.toDouble() / route.volumeMax.toDouble(),
                    )
                )
            }
        }
    }

    private val routeSelector: MediaRouteSelector = MediaRouteSelector.Builder()
        .addControlCategory(CastMediaControlIntent.categoryForCast(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID))
        .build()

    fun start() {
        castContext?.sessionManager?.addSessionManagerListener(sessionListener, CastSession::class.java)
        mediaRouter.addCallback(routeSelector, routerCallback, MediaRouter.CALLBACK_FLAG_UNFILTERED_EVENTS)
    }

    private fun emit(event: Map<String, Any?>) {
        val sink = onEvent ?: return
        handler.post { sink(event) }
    }

    private fun attachMediaClientListener(session: CastSession) {
        val client = session.remoteMediaClient ?: return
        detachMediaClientListener()
        attachedClient = client
        val callback = object : RemoteMediaClient.Callback() {
            override fun onStatusUpdated() {
                emitStatus(client)
                emitVolumeIfChanged()
            }
        }
        mediaClientCallback = callback
        client.registerCallback(callback)
        startStatusTicker(client)
    }

    private fun detachMediaClientListener() {
        stopStatusTicker()
        val cb = mediaClientCallback
        if (cb != null) attachedClient?.unregisterCallback(cb)
        mediaClientCallback = null
        attachedClient = null
        lastVolume = null
    }

    // ponytail: RemoteMediaClient only pushes on status boundaries; a 1s tick
    // keeps the Dart-side position slider moving between them, mirroring the
    // DLNA polling path.
    private fun startStatusTicker(client: RemoteMediaClient) {
        stopStatusTicker()
        val tick = object : Runnable {
            override fun run() {
                if (connectedSession == null) return
                if (client.isPlaying) emitStatus(client)
                emitVolumeIfChanged()
                handler.postDelayed(this, 1000L)
            }
        }
        statusTicker = tick
        handler.postDelayed(tick, 1000L)
    }

    private fun stopStatusTicker() {
        statusTicker?.let { handler.removeCallbacks(it) }
        statusTicker = null
    }

    private fun emitStatus(client: RemoteMediaClient) {
        emit(
            mapOf(
                "event" to "status",
                "position" to client.approximateStreamPosition,
                "duration" to client.streamDuration,
                "playing" to client.isPlaying,
                "sourceError" to (client.mediaStatus?.idleReason == MediaStatus.IDLE_REASON_ERROR),
            )
        )
    }

    fun discover(): List<Map<String, Any>> {
        // ponytail: MediaRouter exposes no selector-filtered getRoutes(); pull all
        // and keep remote-playback routes (Cast devices surface here).
        val routes = mediaRouter.routes
        val out = mutableListOf<Map<String, Any>>()
        for (r in routes) {
            if (r.isDefault) continue
            if (!r.matchesSelector(routeSelector)) continue
            out.add(
                mapOf(
                    "id" to (r.id.toString()),
                    "name" to (r.name?.toString() ?: "Chromecast"),
                )
            )
        }
        return out
    }

    fun connect(deviceId: String, result: MethodChannel.Result) {
        val manager = castContext?.sessionManager
        if (manager == null) { result.error("CAST_UNAVAILABLE", "Google Cast is unavailable on this device.", null); return }
        if (pendingConnect != null || pendingDisconnect != null) {
            result.error("CAST_BUSY", "Wait for the current Cast connection change.", null); return
        }
        val target = mediaRouter.routes.firstOrNull { it.id == deviceId && it.matchesSelector(routeSelector) }
        if (target == null) { result.error("CAST_DEVICE", "The Cast receiver is no longer available. Scan again.", null); return }
        disconnectRequested = false
        val existing = manager.currentCastSession
        if (existing?.isConnected == true && mediaRouter.selectedRoute.id == deviceId) {
            connectedSession = existing
            attachMediaClientListener(existing)
            result.success(null)
            return
        }
        pendingRouteId = deviceId
        connectionMayBeStarting = true
        pendingConnect = CastPendingReply(result, handler,
            onFinished = { pendingConnect = null; pendingRouteId = null })
        try { mediaRouter.selectRoute(target) }
        catch (_: Exception) { sessionFailed(-1) }
    }

    fun disconnect(result: MethodChannel.Result) {
        if (pendingDisconnect != null) { result.error("CAST_BUSY", "Wait for receiver shutdown.", null); return }
        disconnectRequested = true
        pendingConnect?.fail("CAST_CANCELLED", "The Cast connection was cancelled.")
        failMediaReplies()
        val manager = castContext?.sessionManager
        val session = connectedSession ?: manager?.currentCastSession
        if (session == null && !connectionMayBeStarting) {
            detachMediaClientListener()
            result.success(null)
            return
        }
        pendingDisconnect = CastPendingReply(result, handler, onFinished = { pendingDisconnect = null })
        try {
            manager?.endCurrentSession(true)
            mediaRouter.selectRoute(mediaRouter.defaultRoute)
        } catch (_: Exception) {
            pendingDisconnect?.fail("CAST_DISCONNECT", "The receiver could not confirm shutdown.")
        }
    }

    private fun client(): RemoteMediaClient? = connectedSession?.remoteMediaClient
        ?: castContext?.sessionManager?.currentCastSession?.takeIf { it.isConnected }?.remoteMediaClient

    private fun failMediaReplies() {
        for (reply in mediaReplies.toList()) reply.fail("CAST_ENDED", "The Cast session is no longer available.")
    }

    private fun command(result: MethodChannel.Result, action: (RemoteMediaClient) -> PendingResult<RemoteMediaClient.MediaChannelResult>) {
        val client = client()
        if (client == null) { result.error("CAST_NOT_CONNECTED", "Connect to a Cast receiver before sending media.", null); return }
        lateinit var reply: CastPendingReply
        reply = CastPendingReply(result, handler, onFinished = { mediaReplies.remove(reply) })
        mediaReplies.add(reply)
        try {
            action(client).setResultCallback { response ->
                if (response.status.isSuccess) reply.succeed()
                else reply.fail("CAST_COMMAND", "The receiver rejected the media operation (status ${response.status.statusCode}).")
            }
        } catch (_: Exception) {
            reply.fail("CAST_COMMAND", "The media operation could not reach the receiver.")
        }
    }

    fun load(url: String, title: String?, artist: String?, contentType: String?, autoplay: Boolean,
             positionMs: Long, result: MethodChannel.Result) {
        val request = try { castMediaLoad(url, title, artist, contentType, autoplay, positionMs) }
        catch (_: IllegalArgumentException) {
            result.error("CAST_SOURCE", "The receiver needs a reachable HTTP audio source.", null); return
        }
        command(result) { it.load(request) }
    }

    fun play(result: MethodChannel.Result) = command(result) { it.play() }
    fun pause(result: MethodChannel.Result) = command(result) { it.pause() }
    fun stop(result: MethodChannel.Result) = command(result) { it.stop() }
    fun seek(positionMs: Long, result: MethodChannel.Result) = command(result) {
        it.seek(MediaSeekOptions.Builder().setPosition(positionMs.coerceAtLeast(0)).build())
    }
    fun setVolume(volume: Double, result: MethodChannel.Result) = command(result) { it.setStreamVolume(volume.coerceIn(0.0, 1.0)) }

    private fun emitVolumeIfChanged() {
        val v = currentVolume() ?: return
        if (v != lastVolume) { lastVolume = v; emit(mapOf("event" to "volume", "volume" to v)) }
    }
    private fun currentVolume(): Double? = try {
        (connectedSession ?: castContext?.sessionManager?.currentCastSession)?.volume
    } catch (_: Exception) { null }
    fun getVolume(): Double? = currentVolume()

    // ponytail: local audio output route selection via MediaRouter.
    // Covers Speaker / Wired / Bluetooth / USB — complements the USB DAC & BT
    // settings already in the app. System routes are included here intentionally.
    fun getOutputRoutes(): List<Map<String, Any>> {
        val routes = mediaRouter.routes
        val out = mutableListOf<Map<String, Any>>()
        for (r in routes) {
            // Remote receivers need a confirmed media handoff, not a local
            // route switch that launches an empty Cast receiver app.
            if (r.isDefault || r.playbackType != MediaRouter.RouteInfo.PLAYBACK_TYPE_LOCAL) continue
            out.add(
                mapOf(
                    "id" to r.id.toString(),
                    "name" to (r.name?.toString() ?: "Output"),
                    "type" to outputTypeLabel(r),
                    "selected" to r.isSelected,
                )
            )
        }
        return out
    }

    fun selectOutputRoute(deviceId: String): Boolean {
        val target = mediaRouter.routes.firstOrNull { it.id.toString() == deviceId && it.playbackType == MediaRouter.RouteInfo.PLAYBACK_TYPE_LOCAL } ?: return false
        mediaRouter.selectRoute(target)
        return true
    }

    private fun outputTypeLabel(r: MediaRouter.RouteInfo): String {
        return when (r.deviceType) {
            MediaRouter.RouteInfo.DEVICE_TYPE_SPEAKER -> "Speaker"
            MediaRouter.RouteInfo.DEVICE_TYPE_BLUETOOTH -> "Bluetooth"
            MediaRouter.RouteInfo.DEVICE_TYPE_TV -> "TV / Receiver"
            MediaRouter.RouteInfo.DEVICE_TYPE_GROUP -> "Group"
            else -> "Other"
        }
    }
}
