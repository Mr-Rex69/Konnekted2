package com.mossapps.flick

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * User-initiated foreground lifetime for embedded Soulseek uploads/downloads.
 * Unlike an external Seeker process this keeps Lokal's own Rust process alive.
 * Android 15+ still enforces its dataSync foreground-service time budget.
 */
class SoulseekForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Soulseek sharing and transfers",
                NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || intent.action == "stop") {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        ServiceCompat.startForeground(
            this,
            ID,
            notification(intent.getBooleanExtra("sharing", false)),
            if (Build.VERSION.SDK_INT >= 29)
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        )

        if (wakeLock == null) {
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Lokal:Soulseek")
                .apply { setReferenceCounted(false) }
        }
        // Every explicit app status update renews a bounded lock. Never keep
        // an unbounded wake lock after transfers finish or the app signs out.
        wakeLock?.acquire(6 * 60 * 1000L)

        if (wifiLock == null) {
            @Suppress("DEPRECATION")
            val lock = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager)
                .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Lokal:Soulseek")
                .apply { setReferenceCounted(false) }
            wifiLock = lock
            lock.acquire()
        }
        return START_NOT_STICKY
    }

    private fun notification(sharing: Boolean): Notification {
        val open = PendingIntent.getActivity(
            this, ID,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Lokal Soulseek")
            .setContentText(if (sharing) "Sharing your main music folder and transferring files"
                else "Downloading music from Soulseek")
            .setContentIntent(open)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // A deliberate task dismissal should not leave the phone sharing.
        stopSelf()
    }

    override fun onDestroy() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        if (wifiLock?.isHeld == true) wifiLock?.release()
        wakeLock = null
        wifiLock = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "lokal_soulseek"
        private const val ID = 1061

        fun register(messenger: BinaryMessenger, context: Context) {
            MethodChannel(messenger, "lokal/soulseek_background").setMethodCallHandler {
                call, result ->
                if (call.method !in setOf("start", "update", "stop")) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val intent = Intent(context, SoulseekForegroundService::class.java)
                    .setAction(call.method)
                    .putExtra("sharing", call.argument<Boolean>("sharing") == true)
                try {
                    if (call.method == "start") {
                        ContextCompat.startForegroundService(context, intent)
                    } else {
                        context.startService(intent)
                    }
                    result.success(null)
                } catch (_: Exception) {
                    result.error("SOULSEEK_BACKGROUND_UNAVAILABLE",
                        "Android could not keep Soulseek active in background. "
                            + "Keep Lokal open while transferring or sharing.", null)
                }
            }
        }
    }
}
