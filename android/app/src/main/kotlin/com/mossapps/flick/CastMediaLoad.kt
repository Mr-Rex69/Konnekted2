package com.mossapps.flick

import android.net.Uri
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata

internal fun castMediaLoad(
    url: String, title: String?, artist: String?, contentType: String?,
    autoplay: Boolean, positionMs: Long,
): MediaLoadRequestData {
    val uri = Uri.parse(url)
    require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrEmpty() && uri.userInfo == null) {
        "The receiver needs a reachable HTTP audio source."
    }
    val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK)
    title?.let { meta.putString(MediaMetadata.KEY_TITLE, it) }
    artist?.let { meta.putString(MediaMetadata.KEY_ARTIST, it) }
    val info = MediaInfo.Builder(url).setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
        .setContentType(contentType?.takeUnless { it.contains('*') } ?: "application/octet-stream")
        .setMetadata(meta).build()
    return MediaLoadRequestData.Builder().setMediaInfo(info).setAutoplay(autoplay)
        .setCurrentTime(positionMs.coerceAtLeast(0)).build()
}
