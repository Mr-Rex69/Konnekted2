package com.mossapps.flick

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/** Android owns mDNS sockets; browsing is explicit and bounded, with manual IP fallback. */
object LokalDesktopDiscovery {
    private const val NETWORK_PERMISSION_REQUEST = 64123
    private var pendingPermission: MethodChannel.Result? = null
    fun handlePermissionResult(requestCode: Int, grants: IntArray): Boolean {
        if (requestCode != NETWORK_PERMISSION_REQUEST) return false
        pendingPermission?.success(grants.isNotEmpty() && grants[0] == android.content.pm.PackageManager.PERMISSION_GRANTED)
        pendingPermission = null
        return true
    }
    fun register(messenger: BinaryMessenger, activity: android.app.Activity) {
        val context = activity.applicationContext
        val handler = Handler(Looper.getMainLooper())
        var active = false
        MethodChannel(messenger, "lokal/desktop_link").setMethodCallHandler { call, result ->
            if (call.method == "getDeviceName") {
                val configured = try {
                    android.provider.Settings.Global.getString(context.contentResolver, "device_name")?.trim()
                } catch (_: SecurityException) { null }
                val model = android.os.Build.MODEL.trim().takeUnless { it.equals("unknown", true) }.orEmpty()
                val maker = android.os.Build.MANUFACTURER.trim().takeUnless { it.equals("unknown", true) }.orEmpty()
                val fallback = if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model".trim()
                result.success(configured?.takeIf { it.isNotBlank() } ?: fallback.ifBlank { "Android device" })
                return@setMethodCallHandler
            }
            if (call.method == "requestLocalNetwork") {
                val permission = "android.permission.ACCESS_LOCAL_NETWORK"
                if (android.os.Build.VERSION.SDK_INT < 37 || activity.checkSelfPermission(permission) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else if (pendingPermission != null) {
                    result.error("busy", "A local-network permission request is already open.", null)
                } else {
                    pendingPermission = result
                    activity.requestPermissions(arrayOf(permission), NETWORK_PERMISSION_REQUEST)
                }
                return@setMethodCallHandler
            }
            if (call.method == "stageAudio") {
                val raw = call.argument<String>("uri")
                val extension = call.argument<String>("extension") ?: "bin"
                if (raw == null || !raw.startsWith("content://") || !extension.matches(Regex("[A-Za-z0-9]{1,8}"))) {
                    result.error("invalid_uri", "Choose a readable audio document.", null)
                    return@setMethodCallHandler
                }
                Thread {
                    val target = java.io.File(context.cacheDir, "lokal-upload-${java.util.UUID.randomUUID()}.$extension")
                    try {
                        val input = context.contentResolver.openInputStream(android.net.Uri.parse(raw))
                            ?: throw java.io.IOException("Audio document could not be opened.")
                        input.use { source -> target.outputStream().use { output ->
                            val buffer = ByteArray(65536)
                            var total = 0L
                            while (true) {
                                val read = source.read(buffer)
                                if (read < 0) break
                                total += read
                                if (total > 1024L * 1024L * 1024L) throw java.io.IOException("Audio file exceeds the upload limit.")
                                output.write(buffer, 0, read)
                            }
                        } }
                        handler.post { result.success(target.absolutePath) }
                    } catch (_: Exception) {
                        target.delete()
                        handler.post { result.error("read_failed", "Audio document could not be read.", null) }
                    }
                }.start()
                return@setMethodCallHandler
            }
            if (call.method != "discover") { result.notImplemented(); return@setMethodCallHandler }
            if (active) { result.error("busy", "Discovery is already running.", null); return@setMethodCallHandler }
            active = true
            val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
            val found = linkedMapOf<String, Map<String, Any>>()
            val finished = AtomicBoolean(false)
            lateinit var listener: NsdManager.DiscoveryListener
            val finish = Runnable {
                if (finished.compareAndSet(false, true)) {
                    active = false
                    try { manager.stopServiceDiscovery(listener) } catch (_: Exception) {}
                    result.success(found.values.toList())
                }
            }
            val queue = java.util.ArrayDeque<NsdServiceInfo>()
            var resolving = false
            fun resolveNext() {
                if (resolving || finished.get() || queue.isEmpty()) return
                resolving = true
                val info = queue.removeFirst()
                @Suppress("DEPRECATION")
                try { manager.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(service: NsdServiceInfo, error: Int) {
                        handler.post { resolving = false; resolveNext() }
                    }
                    override fun onServiceResolved(service: NsdServiceInfo) {
                        handler.post {
                            val address = service.host?.hostAddress
                            fun txt(key: String) = service.attributes[key]?.toString(Charsets.UTF_8)
                            if (!finished.get() && address != null && txt("proto") == "1") {
                                found[txt("id") ?: service.serviceName] = mapOf(
                                    "id" to (txt("id") ?: service.serviceName),
                                    "name" to (txt("name") ?: service.serviceName),
                                    "host" to address, "port" to service.port,
                                )
                            }
                            resolving = false
                            resolveNext()
                        }
                    }
                }) } catch (_: Exception) { resolving = false; resolveNext() }
            }
            listener = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(type: String) {}
                override fun onDiscoveryStopped(type: String) {}
                override fun onStartDiscoveryFailed(type: String, error: Int) { handler.post(finish) }
                override fun onStopDiscoveryFailed(type: String, error: Int) {}
                override fun onServiceLost(info: NsdServiceInfo) {}
                override fun onServiceFound(info: NsdServiceInfo) {
                    handler.post {
                        if (!finished.get() && info.serviceType.startsWith("_lokal._tcp")) {
                            queue.addLast(info)
                            resolveNext()
                        }
                    }
                }
            }
            try {
                manager.discoverServices("_lokal._tcp.", NsdManager.PROTOCOL_DNS_SD, listener)
                handler.postDelayed(finish, 4500)
            } catch (_: Exception) { handler.post(finish) }
        }
    }
}
