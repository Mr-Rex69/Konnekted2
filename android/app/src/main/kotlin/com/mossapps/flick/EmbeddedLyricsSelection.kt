package com.mossapps.flick

/** Pure tag selection for embedded FLAC/ID3 lyrics. Does not alter the tag. */
internal object EmbeddedLyricsSelection {
    private val lrcStampPattern = Regex("""\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?]""")
    private val lrcMetaPattern = Regex(
        """^\[(?:ar|ti|al|au|by|re|ve|length|offset|id|hash|sign|qq|total|#)\s*:""",
        RegexOption.IGNORE_CASE,
    )
    private val backgroundPattern = Regex("""^\s*\[bg\s*:""", RegexOption.IGNORE_CASE)

    /** Desktop's native VORBIS_COMMENT stores the complete background lane as
     * structured JSON; a second LYRICS entry contains only the portable lead.
     */
    private val lokalVersion = Regex(""""lokal"\\s*:\\s*1(?:\\s*[,}])""")
    private val lokalLines = Regex(""""lines"\\s*:\\s*\\[""")
    private fun isLokalPrivate(text: String): Boolean =
        text.trimStart().startsWith("{") &&
            lokalVersion.containsMatchIn(text) && lokalLines.containsMatchIn(text)

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
        val primary = candidates.firstOrNull(::isLokalPrivate) ?: pick(candidates) ?: return null
        if (isLokalPrivate(primary)) return primary
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
        var privateLyrics: String? = null
        repeat(commentCount) {
            val size = length() ?: return combineVorbisLyrics(found)
            val bytes = ByteArray(size)
            buffer.get(bytes)
            val entry = bytes.toString(Charsets.UTF_8)
            val equal = entry.indexOf('=')
            if (equal <= 0) return@repeat
            val key = entry.substring(0, equal).uppercase(java.util.Locale.ROOT)
            val value = entry.substring(equal + 1).trim()
            if (key == "LOKAL_LYRICS" && isLokalPrivate(value)) privateLyrics = value
            else if (key in wanted && value.isNotBlank()) found.add(value)
        }
        return privateLyrics ?: combineVorbisLyrics(found)
    }

    /**
     * Read FLAC's actual metadata stream, not just a synthetic lyric string.
     * The stream may contain STREAMINFO and other blocks before VORBIS_COMMENT.
     */
    fun fromFlac(input: java.io.InputStream): String? {
        fun readExact(bytes: ByteArray): Boolean {
            var offset = 0
            while (offset < bytes.size) {
                val amount = input.read(bytes, offset, bytes.size - offset)
                if (amount <= 0) return false
                offset += amount
            }
            return true
        }
        val magic = ByteArray(4)
        if (!readExact(magic) || !magic.contentEquals("fLaC".toByteArray(Charsets.US_ASCII))) {
            return null
        }
        var last = false
        while (!last) {
            val blockHeader = ByteArray(4)
            if (!readExact(blockHeader)) return null
            val type = blockHeader[0].toInt() and 0x7f
            last = (blockHeader[0].toInt() and 0x80) != 0
            val length = ((blockHeader[1].toInt() and 0xff) shl 16) or
                ((blockHeader[2].toInt() and 0xff) shl 8) or
                (blockHeader[3].toInt() and 0xff)
            if (type == 4) {
                val data = ByteArray(length)
                if (!readExact(data)) return null
                return fromVorbisComments(data)
            }
            // Reading in small chunks handles SAF providers whose InputStream
            // does not implement skip() reliably.
            var remaining = length
            val scratch = ByteArray(8192)
            while (remaining > 0) {
                val amount = input.read(scratch, 0, minOf(scratch.size, remaining))
                if (amount <= 0) return null
                remaining -= amount
            }
        }
        return null
    }

    /** The original timed tag with independent backing singers is more complete. */
    fun pick(candidates: List<String>): String? {
        val parts = candidates.filter { it.isNotBlank() }
        parts.firstOrNull(::isLokalPrivate)?.let { return it }
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
