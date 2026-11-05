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
}
