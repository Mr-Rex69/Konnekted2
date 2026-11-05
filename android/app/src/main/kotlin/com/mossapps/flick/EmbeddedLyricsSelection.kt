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
