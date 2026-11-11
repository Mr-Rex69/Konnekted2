package com.mossapps.flick

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class PlaybackStagingGateTest {
    @Test fun sameSourceCopyWaitsForTheExistingWriter() {
        val workers = Executors.newFixedThreadPool(2)
        val entered = CountDownLatch(1)
        val attempted = CountDownLatch(1)
        val secondEntered = CountDownLatch(1)
        val release = CountDownLatch(1)
        try {
            val first = workers.submit {
                PlaybackStagingGate.withUri("content://songs/one") {
                    entered.countDown()
                    assertTrue(release.await(5, TimeUnit.SECONDS))
                }
            }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val second = workers.submit {
                attempted.countDown()
                PlaybackStagingGate.withUri("content://songs/one") { secondEntered.countDown() }
            }
            assertTrue(attempted.await(5, TimeUnit.SECONDS))
            assertFalse(secondEntered.await(150, TimeUnit.MILLISECONDS))
            release.countDown()
            first.get(5, TimeUnit.SECONDS)
            second.get(5, TimeUnit.SECONDS)
            assertEquals(0L, secondEntered.count)
        } finally {
            release.countDown()
            workers.shutdownNow()
        }
    }

    @Test fun unrelatedSourcesCanCopyConcurrently() {
        val workers = Executors.newFixedThreadPool(2)
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        try {
            val first = workers.submit {
                PlaybackStagingGate.withUri("content://songs/one") {
                    entered.countDown()
                    release.await(5, TimeUnit.SECONDS)
                }
            }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val second = workers.submit<String> {
                PlaybackStagingGate.withUri("content://songs/two") { "ready" }
            }
            assertEquals("ready", second.get(5, TimeUnit.SECONDS))
            release.countDown()
            first.get(5, TimeUnit.SECONDS)
        } finally {
            release.countDown()
            workers.shutdownNow()
        }
    }
}
