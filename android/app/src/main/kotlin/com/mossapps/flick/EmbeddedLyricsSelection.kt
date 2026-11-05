package com.mossapps.flick

/** Pure tag selection for embedded FLAC/ID3 lyrics. Does not alter the tag. */
internal object EmbeddedLyricsSelection {
    private val lrcStampPattern = Regex("""\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?]""")
    private val lrcMetaPattern = Regex(
        """^\[(?:ar|ti|al|au|by|re|ve|length|offset|id|hash|sign|qq|total|#)\s*:""",
        RegexOption.IGNORE_CASE,
    )
    private val backgroundPattern = Regex("""^\s*\[bg\s*:""", RegexOption.IGNORE_CASE)

    private fun backgroundCount(text: String): Int =
        text.lineSequence().count { backgroundPattern.containsMatchIn(it) }

    /** Adjacent unstamped lines are translations; [bg:] is a vocal, not a translation. */
    private fun translationScore(text: String): Int {
        var score = 0
        var afterStamped = false
        for (raw in text.replace("\r\n", "\n").replace('\r', '\n').split('\n')) {
            val line = raw.trim()
            if (line.isEmpty()) {
                afterStamped = false
                continue
            }
            if (lrcStampPattern.containsMatchIn(line)) {
                afterStamped = true
                continue
            }
            if (afterStamped && !lrcMetaPattern.containsMatchIn(line) &&
                !backgroundPattern.containsMatchIn(line)) score++
            afterStamped = false
        }
        return score
    }

    /**
     * Vorbis stores lyrics in separate comment entries. A file may put lead
     * timing in LYRICS and independent [bg:] rows in UNSYNCEDLYRICS.
     * Choosing one entry discards the other voice. Merge only the missing
     * [bg:] rows from the *same file*, never duplicate already present rows.
     */
    fun combineVorbisLyrics(candidates: List<String>): String? {
        val primary = pick(candidates) ?: return null
        val seen = primary.lineSequence().map { it.trim() }.toMutableSet()
        val extraBacking = candidates.asSequence()
            .flatMap { it.replace("\r\n", "\n").replace('\r', '\n').lineSequence() }
            .map { it.trim() }
            .filter { backgroundPattern.containsMatchIn(it) && seen.add(it) }
            .toList()
        return if (extraBacking.isEmpty()) primary
        else primary.trimEnd() + "\n" + extraBacking.joinToString("\n")
    }

    /**
     * Decode the FLAC VORBIS_COMMENT metadata block independently from Android
     * MediaMetadataRetriever so valid FLAC files remain readable if Android's
     * platform metadata decoder rejects their URI.
     */
    fun fromVorbisComments(data: ByteArray): String? {
        if (data.size < 8) return null
        val buffer = java.nio.ByteBuffer.wrap(data)
            .order(java.nio.ByteOrder.LITTLE_ENDIAN)

        fun length(): Int? {
            if (buffer.remaining() < Int.SIZE_BYTES) return null
            val count = buffer.int
            return count.takeIf { it >= 0 && it <= buffer.remaining() }
        }

        val vendorLength = length() ?: return null
        buffer.position(buffer.position() + vendorLength)
        if (buffer.remaining() < Int.SIZE_BYTES) return null
        val commentCount = buffer.int
        if (commentCount < 0 || commentCount > 100000) return null

        val wanted = setOf(
            "LYRICS", "UNSYNCEDLYRICS", "UNSYNCED_LYRICS",
            "SYNCEDLYRICS", "SYNCED_LYRICS",
        )
        val found = mutableListOf<String>()
        repeat(commentCount) {
            val size = length() ?: return combineVorbisLyrics(found)
            val bytes = ByteArray(size)
            buffer.get(bytes)
            val entry = bytes.toString(Charsets.UTF_8)
            val equal = entry.indexOf('=')
            if (equal <= 0) return@repeat
            val key = entry.substring(0, equal).uppercase(java.util.Locale.ROOT)
            val value = entry.substring(equal + 1).trim()
            if (key in wanted && value.isNotBlank()) found.add(value)
        }
        return combineVorbisLyrics(found)
    }

    /** The original timed tag with independent backing singers is more complete. */
    fun pick(candidates: List<String>): String? {
        val parts = candidates.filter { it.isNotBlank() }
        val synced = parts.filter { lrcStampPattern.containsMatchIn(it) }
        if (synced.isEmpty()) return parts.firstOrNull()
        return synced.reduce { best, candidate ->
            val moreBacking = backgroundCount(candidate) - backgroundCount(best)
            when {
                moreBacking > 0 -> candidate
                moreBacking < 0 -> best
                translationScore(candidate) > translationScore(best) -> candidate
                else -> best
            }
        }
    }
}
