package com.mossapps.flick

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Validate the real GitHub release path, never an arbitrary URL prefix.
 * GitHub redirects previous repository aliases to lokal-music/Mobile.
 */
internal fun isTrustedLokalReleaseApkUrl(url: String): Boolean {
    val uri = try { URI(url) } catch (_: java.net.URISyntaxException) { return false }
    if (uri.scheme != "https" ||
        !uri.host.equals("github.com", ignoreCase = true) ||
        uri.rawUserInfo != null ||
        uri.port != -1 ||
        uri.rawQuery != null ||
        uri.rawFragment != null
    ) return false
    val parts = (uri.rawPath ?: return false).removePrefix("/").split("/")
    return parts.size == 6 &&
        "${parts[0].lowercase()}/${parts[1].lowercase()}" in setOf(
            "lokal-music/mobile",
            "lokal-music/lokal-mobile",
            "lokal-konnekt/lokal-mobile"
        ) &&
        parts[2] == "releases" &&
        parts[3] == "download" &&
        parts[4].isNotBlank() &&
        parts[5].startsWith("Lokal-") &&
        parts[5].endsWith(".apk") &&
        !parts[5].contains("%")
}

/** Downloads survive leaving the app; Android always confirms installation. */
object LokalAppUpdater {
    var systemUiOpen = false
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private const val MIME = "application/vnd.android.package-archive"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        val context = activity.applicationContext
        val prefs = context.getSharedPreferences("lokal_app_update", Context.MODE_PRIVATE)
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        fun file() = File(requireNotNull(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)) { "Update storage is unavailable" }, "lokal-update.apk")
        MethodChannel(messenger, "lokal/app_update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "download" -> {
                        check(BuildConfig.FLAVOR == "full") { "Use GitHub Releases for this APK variant" }
                        val url = call.argument<String>("url").orEmpty()
                        val hash = call.argument<String>("sha256").orEmpty()
                        val code = call.argument<Number>("build")?.toLong() ?: 0L
                        require(isTrustedLokalReleaseApkUrl(url)) { "Invalid Lokal release download URL" }
                        require(hash.matches(Regex("[a-fA-F0-9]{64}")) && code > BuildConfig.VERSION_CODE)
                        val old = prefs.getLong("id", -1)
                        if (old != -1L) manager.remove(old)
                        file().delete()
                        val request = DownloadManager.Request(Uri.parse(url))
                            .setTitle("Lokal update")
                            .setDescription("Downloading the new Lokal APK")
                            .setMimeType(MIME)
                            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, "lokal-update.apk")
                        val id = manager.enqueue(request)
                        prefs.edit().putLong("id", id).putString("sha256", hash.lowercase()).putLong("build", code).apply()
                        result.success(null)
                    }
                    "status" -> {
                        val id = prefs.getLong("id", -1)
                        var status = "none"
                        var bytes = 0L
                        var total = 0L
                        if (id != -1L) manager.query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
                            if (cursor.moveToFirst()) {
                                status = when (cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                                    DownloadManager.STATUS_SUCCESSFUL -> "ready"
                                    DownloadManager.STATUS_FAILED -> "failed"
                                    else -> "downloading"
                                }
                                bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                                total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                            }
                        }
                        result.success(mapOf("status" to status, "bytes" to bytes, "total" to total, "build" to prefs.getLong("build", 0)))
                    }
                    "install" -> {
                        check(BuildConfig.FLAVOR == "full") { "Use GitHub Releases for this APK variant" }
                        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
                            systemUiOpen = true
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${context.packageName}")))
                            result.success("permission")
                        } else {
                            worker.execute {
                                try {
                                    val apk = file()
                                    val expected = prefs.getString("sha256", "").orEmpty()
                                    check(expected.isNotEmpty() && apk.isFile) { "Download the update again" }
                                    val digest = MessageDigest.getInstance("SHA-256")
                                    apk.inputStream().use { input ->
                                        val buffer = ByteArray(128 * 1024)
                                        while (true) {
                                            val count = input.read(buffer)
                                            if (count < 0) break
                                            digest.update(buffer, 0, count)
                                        }
                                    }
                                    check(digest.digest().joinToString("") { "%02x".format(it) } == expected) { "Update checksum mismatch. Download it again." }
                                    val info = context.packageManager.getPackageArchiveInfo(apk.path, 0)
                                        ?: error("The downloaded APK is invalid")
                                    val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
                                        @Suppress("DEPRECATION")
                                        info.versionCode.toLong()
                                    }
                                    check(info.packageName == context.packageName && code == prefs.getLong("build", 0) && code > BuildConfig.VERSION_CODE) { "Update package or build does not match" }
                                    main.post {
                                        try {
                                            val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
                                            systemUiOpen = true
                                            activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, MIME)
                                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                            result.success("opened")
                                        } catch (error: Exception) {
                                            systemUiOpen = false
                                            result.error("INSTALL_FAILED", error.message, null)
                                        }
                                    }
                                } catch (error: Exception) {
                                    main.post { result.error("INSTALL_FAILED", error.message, null) }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                systemUiOpen = false
                result.error("UPDATE_FAILED", error.message, null)
            }
        }
    }
}
