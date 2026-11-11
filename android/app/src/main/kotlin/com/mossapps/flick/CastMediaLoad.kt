package com.mossapps.flick

import android.net.Uri
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata

internal fun castMediaLoad(
    url: String, title: String?, artist: String?, contentType: String?,
    autoplay: Boolean, positionMs: Long, album: String? = null, artwork: String? = null, trackId: String? = null, loadId: String? = null,
): MediaLoadRequestData {
    val uri = Uri.parse(url)
    require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrEmpty() && uri.userInfo == null) {
        "The receiver needs a reachable HTTP audio source."
    }
    val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK)
    title?.let { meta.putString(MediaMetadata.KEY_TITLE, it) }
    artist?.let { meta.putString(MediaMetadata.KEY_ARTIST, it) }
    album?.let { meta.putString(MediaMetadata.KEY_ALBUM_TITLE, it) }
    artwork?.let {
        val image = Uri.parse(it)
        if (image.scheme in listOf("http", "https") && !image.host.isNullOrEmpty())
            meta.addImage(com.google.android.gms.common.images.WebImage(image))
    }
    val info = MediaInfo.Builder(url).setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
        .setContentType(contentType?.takeUnless { it.contains('*') } ?: "application/octet-stream")
        .setMetadata(meta).setCustomData(org.json.JSONObject(mapOf("lokal" to 1, "trackId" to trackId, "loadId" to loadId))).build()
    return MediaLoadRequestData.Builder().setMediaInfo(info).setAutoplay(autoplay)
        .setCurrentTime(positionMs.coerceAtLeast(0)).build()
}

/** A missing terminal mediaInfo retains identity; replacement media never does. */
internal class CastMediaIdentity {
    var loadId: String? = null
        private set
    var trackId: String? = null
        private set
    fun update(info: MediaInfo?) {
        if (info == null) return
        loadId = (info.customData?.opt("loadId") as? String)?.takeIf { it.isNotBlank() }
        trackId = if (loadId != null) (info.customData?.opt("trackId") as? String)?.takeIf { it.isNotBlank() } else null
    }
    fun clear() { loadId = null; trackId = null }
}
