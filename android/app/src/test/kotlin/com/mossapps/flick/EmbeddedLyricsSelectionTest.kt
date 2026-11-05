package com.mossapps.flick

import org.junit.Assert.assertEquals
import org.junit.Test

class EmbeddedLyricsSelectionTest {
    @Test
    fun prefersSynchronizedFLACPayloadWithBackingOverLeadOnlyTwin() {
        val leadOnly = "[00:15.433]<00:15.433>Lead<00:22.852>"
        val complete = "$leadOnly\n[bg:<00:17.254><00:17.254>Voice<00:21.736>]"
        assertEquals(complete, EmbeddedLyricsSelection.pick(listOf(leadOnly, complete)))
        assertEquals(complete, EmbeddedLyricsSelection.pick(listOf(complete, leadOnly)))
    }

    @Test
    fun backingVoiceOutranksExtraTranslations() {
        val leadWithTranslation = "[00:15.433]Lead\nTranslation\n[00:22.852]Next\nTranslation"
        val withBacking = "[00:15.433]Lead\n[bg:<00:17.254>Backing<00:21.736>]\n[00:22.852]Next"
        assertEquals(withBacking, EmbeddedLyricsSelection.pick(listOf(leadWithTranslation, withBacking)))
    }

    @Test
    fun oldTranslationPreferenceStillAppliesWithoutBacking() {
        val plain = "Lead"
        val timed = "[00:15.433]Lead"
        val translated = "$timed\nTranslation"
        assertEquals(translated, EmbeddedLyricsSelection.pick(listOf(plain, timed, translated)))
        assertEquals(plain, EmbeddedLyricsSelection.pick(listOf(plain, "Other")))
    }

    private fun vorbisBlock(vararg entries: String): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        fun int32(value: Int) {
            output.write(value and 0xff)
            output.write((value ushr 8) and 0xff)
            output.write((value ushr 16) and 0xff)
            output.write((value ushr 24) and 0xff)
        }
        val vendor = "fixture-encoder".toByteArray(Charsets.UTF_8)
        int32(vendor.size)
        output.write(vendor)
        int32(entries.size)
        for (entry in entries) {
            val bytes = entry.toByteArray(Charsets.UTF_8)
            int32(bytes.size)
            output.write(bytes)
        }
        return output.toByteArray()
    }

    @Test
    fun mergesBackingRowsFromSeparateVorbisCommentIntoCompleteLeadLyrics() {
        val lead = "[00:15.433]v1:<00:15.433>Lead<00:22.852>\n" +
            "[00:23.055]v1:<00:23.055>Next<00:24.474>"
        val backing = "[bg:<00:17.254><00:17.254>Harmony<00:21.736>]"
        val block = vorbisBlock(
            "UNSYNCEDLYRICS=$backing",
            "LYRICS=$lead",
        )
        val selected = EmbeddedLyricsSelection.fromVorbisComments(block)
        assertEquals(lead + "\n" + backing, selected)
    }

    @Test
    fun duplicateBackingEntriesAcrossVorbisFieldsAreIncludedOnlyOnce() {
        val lead = "[00:15.433]<00:15.433>Lead<00:22.852>"
        val bg = "[bg:<00:17.254><00:17.254>Harmony<00:21.736>]"
        val block = vorbisBlock(
            "LYRICS=$lead\n$bg",
            "UNSYNCEDLYRICS=$lead\n$bg",
        )
        val selected = EmbeddedLyricsSelection.fromVorbisComments(block)!!
        assertEquals(1, selected.lineSequence().count { it.startsWith("[bg:") })
    }

    @Test
    fun independentlyDecodesSyncedLyricTagsAndHandlesBrokenCommentBlocks() {
        val lead = "[00:15.433]<00:15.433>Lead<00:22.852>"
        assertEquals(lead, EmbeddedLyricsSelection.fromVorbisComments(
            vorbisBlock("ARTIST=Fixture", "SYNCEDLYRICS=$lead"),
        ))
        assertEquals(null, EmbeddedLyricsSelection.fromVorbisComments(byteArrayOf(0, 1, 2)))
    }


    private fun flacWithVorbisComments(block: ByteArray): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        out.write("fLaC".toByteArray(Charsets.US_ASCII))
        // STREAMINFO: a 4-byte test block, followed by a final VORBIS_COMMENT.
        out.write(byteArrayOf(0, 0, 0, 4))
        out.write(byteArrayOf(0, 0, 0, 0))
        out.write(byteArrayOf(
            0x84.toByte(),
            ((block.size ushr 16) and 0xff).toByte(),
            ((block.size ushr 8) and 0xff).toByte(),
            (block.size and 0xff).toByte(),
        ))
        out.write(block)
        return out.toByteArray()
    }

    @Test
    fun decodesRealFlacMetadataBlockLayoutAndMergesSplitBackingVocals() {
        val lead = "[00:15.433]<00:15.433>Lead<00:22.852>"
        val backing = "[bg:<00:17.254><00:17.254>Harmony<00:21.736>]"
        val block = vorbisBlock(
            "UNSYNCEDLYRICS=$backing",
            "LYRICS=$lead",
        )
        val flac = flacWithVorbisComments(block)
        assertEquals(
            lead + "\n" + backing,
            EmbeddedLyricsSelection.fromFlac(java.io.ByteArrayInputStream(flac)),
        )
    }

    @Test
    fun skipsUnrelatedFlacBlocksWithoutLosingLyricTags() {
        val input = flacWithVorbisComments(
            vorbisBlock("LYRICS=[00:01.00]Sung"),
        )
        assertEquals(
            "[00:01.00]Sung",
            EmbeddedLyricsSelection.fromFlac(java.io.ByteArrayInputStream(input)),
        )
        assertEquals(
            null,
            EmbeddedLyricsSelection.fromFlac(
                java.io.ByteArrayInputStream("not-flac".toByteArray(Charsets.UTF_8)),
            ),
        )
    }

}
