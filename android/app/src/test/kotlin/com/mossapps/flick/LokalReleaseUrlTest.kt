package com.mossapps.flick

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LokalReleaseUrlTest {
    @Test
    fun canonicalVersionTwoApkIsTrusted() {
        assertTrue(isTrustedLokalReleaseApkUrl(
            "https://github.com/lokal-music/Mobile/releases/download/v2.0.0/Lokal-2.0.0-arm64.apk"
        ))
    }

    @Test
    fun formerRepositoryAliasStillAcceptedForOlderReleases() {
        assertTrue(isTrustedLokalReleaseApkUrl(
            "https://github.com/Lokal-Konnekt/lokal-mobile/releases/download/v1.4.3/Lokal-1.4.3-universal.apk"
        ))
    }

    @Test
    fun arbitraryHostsOrReposCannotSupplyApks() {
        listOf(
            "http://github.com/lokal-music/lokal-mobile/releases/download/v2.0.0/Lokal-2.0.0-arm64.apk",
            "https://github.com.evil.test/lokal-music/lokal-mobile/releases/download/v2.0.0/Lokal-2.0.0-arm64.apk",
            "https://github.com/lokal-music/lokal-mobile-evil/releases/download/v2.0.0/Lokal-2.0.0-arm64.apk",
            "https://github.com@evil.test/lokal-music/lokal-mobile/releases/download/v2.0.0/Lokal-2.0.0-arm64.apk",
            "https://github.com/lokal-music/lokal-mobile/releases/download/v2.0.0/other.apk",
            "https://github.com/lokal-music/Mobile/releases/download/v2.0.0/Lokal-2.0.0-arm64.apk?spoof=1",
            "https://github.com/lokal-music/Mobile/releases/download/v2.0.0/Lokal-2.0.0-arm64.apk#fragment",
            "https://github.com/lokal-music/lokal-mobile/releases/download/v2.0.0/%2e%2e%2fLokal-2.0.0-arm64.apk",
            "https://github.com/lokal-music/lokal-mobile/releases/download/%zz/Lokal-2.0.0-arm64.apk",
        ).forEach { assertFalse("Must reject $it", isTrustedLokalReleaseApkUrl(it)) }
    }
}
