package com.mossapps.flick

/** Playback, artwork and waveform requests share the same URI staging files.
 * Serialize a source's copy/rename, including across Activity recreation.
 * Fixed stripes bound memory without retaining content URIs. */
internal object PlaybackStagingGate {
    private val locks = Array(32) { Any() }

    fun <T> withUri(uri: String, action: () -> T): T =
        synchronized(locks[uri.hashCode() and (locks.size - 1)], action)
}
