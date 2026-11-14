package io.github.asomkhattak.sift

import android.Manifest
import android.app.Activity
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import android.webkit.CookieManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "io.github.asomkhattak.sift/native"
        private const val DOWNLOAD_PERMISSION_REQUEST = 4701
        private const val TAG = "SiftUpdater"
        private const val MIN_APK_BYTES = 500L * 1024L
        private const val MAX_APK_BYTES = 350L * 1024L * 1024L
        private val WEB_SCHEMES = setOf("http", "https")
        private val EXTERNAL_SCHEMES = setOf("http", "https", "mailto", "tel", "sms")
    }

    private class UpdateDownload(val id: String) {
        @Volatile var cancelled = false
        @Volatile var connection: HttpURLConnection? = null
        val finished = AtomicBoolean(false)

        fun cancel() {
            cancelled = true
            try {
                connection?.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    private var channel: MethodChannel? = null
    private var pendingIntent: Map<String, Any?>? = null
    private var pendingDownload: Map<String, Any?>? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var activeUpdate: UpdateDownload? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingIntent = parseIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchIntent" -> {
                    val value = pendingIntent
                    pendingIntent = null
                    result.success(value)
                }

                "openExternal" -> {
                    val url = call.argument<String>("url")
                    result.success(url != null && openExternal(url))
                }

                "shareText" -> {
                    val text = call.argument<String>("text").orEmpty()
                    val title = call.argument<String>("title")
                    val url = call.argument<String>("url")
                    result.success(shareText(text, title, url))
                }

                "download" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename") ?: "sift-download"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val cookie = call.argument<String>("cookie") ?: CookieManager.getInstance().getCookie(url)
                    val userAgent = call.argument<String>("userAgent")
                    if (url == null || !isHttp(url)) {
                        result.success(false)
                    } else {
                        result.success(
                            startDownload(
                                mapOf(
                                    "url" to url,
                                    "filename" to filename,
                                    "mime" to mime,
                                    "cookie" to cookie,
                                    "userAgent" to userAgent,
                                ),
                            ),
                        )
                    }
                }

                "setSecureScreen" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setSecureScreen(enabled)
                    result.success(null)
                }

                "openAppSettings" -> {
                    openAppSettings()
                    result.success(null)
                }

                "getAppVersion" -> result.success(appVersion())

                "downloadUpdate" -> startUpdateDownload(call, result)

                "installUpdate" -> result.success(installUpdate(call.argument("path")))

                "cancelUpdate" -> {
                    cancelUpdate(call.argument("id"))
                    result.success(null)
                }

                "openInstallSettings" -> {
                    openInstallSettings()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // Keep the launch payload until Dart asks for it. The engine is
        // configured before the Dart entrypoint exists, so pushing it from
        // here would race the method-channel handler and lose the intent.
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = parseIntent(intent) ?: return
        if (channel == null) {
            pendingIntent = payload
        } else {
            channel?.invokeMethod("onLaunchIntent", payload)
        }
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }

    private fun parseIntent(source: Intent?): Map<String, Any?>? {
        if (source == null) return null
        return when (source.action) {
            Intent.ACTION_VIEW -> {
                val uri = source.data ?: return null
                when {
                    WEB_SCHEMES.contains(uri.scheme) -> mapOf("url" to uri.toString())
                    uri.scheme == "sift" && uri.host == "search" ->
                        mapOf("query" to (uri.getQueryParameter("q") ?: uri.getQueryParameter("query")))
                    uri.scheme == "sift" && uri.host == "open" ->
                        mapOf("url" to uri.getQueryParameter("url"))
                    else -> null
                }
            }

            Intent.ACTION_SEND -> {
                val text = source.getStringExtra(Intent.EXTRA_TEXT) ?: return null
                mapOf("text" to text)
            }

            Intent.ACTION_PROCESS_TEXT -> {
                val text = source.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
                    ?: return null
                mapOf("text" to text)
            }

            Intent.ACTION_WEB_SEARCH, Intent.ACTION_SEARCH -> {
                val query = source.getStringExtra("query") ?: return null
                mapOf("query" to query)
            }

            else -> null
        }
    }

    private fun isHttp(url: String): Boolean {
        val scheme = Uri.parse(url).scheme ?: return false
        return WEB_SCHEMES.contains(scheme.lowercase())
    }

    private fun openExternal(url: String): Boolean {
        val uri = try {
            Uri.parse(url)
        } catch (_: Exception) {
            return false
        }
        val scheme = uri.scheme?.lowercase()
        if (scheme == null || !EXTERNAL_SCHEMES.contains(scheme)) return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun shareText(text: String, title: String?, url: String?): Boolean {
        val body = when {
            url.isNullOrBlank() -> text
            text.isBlank() -> url
            text.contains(url) -> text
            else -> "$text\n$url"
        }
        if (body.isBlank()) return false
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, body)
            if (!title.isNullOrBlank()) putExtra(Intent.EXTRA_SUBJECT, title)
        }
        return try {
            startActivity(Intent.createChooser(send, title ?: "Share with"))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun startDownload(payload: Map<String, Any?>): Boolean {
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingDownload = payload
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                DOWNLOAD_PERMISSION_REQUEST,
            )
            return true
        }
        return enqueueDownload(payload)
    }

    private fun enqueueDownload(payload: Map<String, Any?>): Boolean {
        val url = payload["url"] as? String ?: return false
        if (!isHttp(url)) return false
        val rawName = payload["filename"] as? String ?: "sift-download"
        val filename = sanitizeFilename(rawName)
        return try {
            val request = DownloadManager.Request(Uri.parse(url)).apply {
                setTitle(filename)
                setDescription("Downloaded with Sift")
                setMimeType(payload["mime"] as? String ?: "application/octet-stream")
                setNotificationVisibility(
                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
                )
                setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename)
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
                (payload["cookie"] as? String)?.takeIf { it.isNotBlank() }?.let {
                    addRequestHeader("Cookie", it)
                }
                (payload["userAgent"] as? String)?.takeIf { it.isNotBlank() }?.let {
                    addRequestHeader("User-Agent", it)
                }
            }
            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            manager.enqueue(request)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun sanitizeFilename(input: String): String {
        val cleaned = input
            .replace(Regex("[/\\\\:*?\"<>|\\u0000-\\u001F]"), "-")
            .trim()
            .trimStart('.')
            .take(120)
        return cleaned.ifBlank { "sift-download" }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != DOWNLOAD_PERMISSION_REQUEST) return
        val payload = pendingDownload
        pendingDownload = null
        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED &&
            payload != null
        ) {
            enqueueDownload(payload)
        }
    }

    private fun appVersion(): Map<String, Any?> {
        return try {
            val info = packageManager.getPackageInfo(packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                info.versionCode.toLong()
            }
            mapOf(
                "name" to (info.versionName ?: "0.0.0"),
                "code" to code,
            )
        } catch (_: Exception) {
            mapOf("name" to "0.0.0", "code" to 0)
        }
    }

    private fun startUpdateDownload(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val url = call.argument<String>("url")
        val fileName = call.argument<String>("fileName")
        val sha256 = call.argument<String>("sha256")
        val sizeBytes = call.argument<Number>("sizeBytes")?.toLong() ?: -1L
        val allowedHost = call.argument<String>("allowedHost")
        if (id.isNullOrBlank() || url.isNullOrBlank() || fileName.isNullOrBlank() ||
            sha256 == null || !Regex("^[0-9a-f]{64}$").matches(sha256) ||
            sizeBytes < MIN_APK_BYTES || sizeBytes > MAX_APK_BYTES
        ) {
            result.success(
                mapOf("ok" to false, "error" to "The update details are incomplete."),
            )
            return
        }
        if (activeUpdate != null) {
            result.success(
                mapOf(
                    "ok" to false,
                    "error" to "Another update is already downloading.",
                ),
            )
            return
        }
        val download = UpdateDownload(id)
        activeUpdate = download
        thread(name = "sift-update", isDaemon = true) {
            val outcome = downloadApk(
                download,
                url,
                fileName,
                sha256,
                sizeBytes,
                allowedHost,
            )
            mainHandler.post {
                if (activeUpdate === download) activeUpdate = null
                if (!download.finished.compareAndSet(false, true)) return@post
                try {
                    result.success(outcome)
                } catch (_: Exception) {
                    // The activity may have gone away while downloading.
                }
            }
        }
    }

    /**
     * Downloads an APK without trusting the manifest: every redirect target is
     * checked against the allowlist, the byte count must match the manifest,
     * and the file only reaches its final name after the SHA-256 matches.
     */
    private fun downloadApk(
        download: UpdateDownload,
        rawUrl: String,
        rawName: String,
        expectedSha: String,
        expectedBytes: Long,
        serviceHost: String?,
    ): Map<String, Any?> {
        var part: File? = null
        try {
            val root = File(cacheDir, "updates")
            if (!root.exists() && !root.mkdirs()) {
                return updateError("Sift could not create the update folder.")
            }
            root.listFiles()?.forEach { file ->
                if (file.isFile) file.delete()
            }
            val name = sanitizeApkName(rawName)
            val target = File(root, name)
            val partFile = File(root, "$name.part")
            part = partFile

            var current = URI(rawUrl)
            var redirects = 0
            var connection: HttpURLConnection? = null
            while (true) {
                if (download.cancelled) return updateCancelled()
                if (!isAllowedUpdateUri(current, serviceHost)) {
                    return updateError("The update address was not trusted.")
                }
                val opened = current.toURL().openConnection() as? HttpURLConnection
                    ?: return updateError("The update address was not valid.")
                connection = opened
                download.connection = opened
                opened.instanceFollowRedirects = false
                opened.connectTimeout = 15_000
                opened.readTimeout = 30_000
                opened.requestMethod = "GET"
                opened.setRequestProperty("User-Agent", "Sift-Android-Updater")
                opened.connect()
                val code = opened.responseCode
                if (code == HttpURLConnection.HTTP_MOVED_PERM ||
                    code == HttpURLConnection.HTTP_MOVED_TEMP ||
                    code == HttpURLConnection.HTTP_SEE_OTHER ||
                    code == 307 ||
                    code == 308
                ) {
                    if (redirects >= 5) {
                        return updateError("The update service redirected too many times.")
                    }
                    val location = opened.getHeaderField("Location")
                        ?: return updateError("The update service sent a bad redirect.")
                    current = current.resolve(location)
                    redirects += 1
                    opened.disconnect()
                    connection = null
                    continue
                }
                if (code !in 200..299) {
                    return updateError("The update service returned HTTP $code.")
                }
                break
            }
            val live = connection
                ?: return updateError("The update address was not valid.")
            val declared = live.contentLengthLong
            if (declared > 0 && declared != expectedBytes) {
                return updateError("The update file size did not match the release.")
            }

            val digest = MessageDigest.getInstance("SHA-256")
            var received = 0L
            FileOutputStream(partFile).use { output ->
                live.inputStream.use { input ->
                    val buffer = ByteArray(64 * 1024)
                    var lastSent = 0L
                    while (true) {
                        if (download.cancelled) return updateCancelled()
                        val read = input.read(buffer)
                        if (read < 0) break
                        received += read
                        if (received > expectedBytes || received > MAX_APK_BYTES) {
                            return updateError("The update file was larger than expected.")
                        }
                        output.write(buffer, 0, read)
                        digest.update(buffer, 0, read)
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastSent >= 140 || received == expectedBytes) {
                            lastSent = now
                            sendUpdateProgress(download.id, received, expectedBytes)
                        }
                    }
                }
                output.flush()
                output.fd.sync()
            }
            if (download.cancelled) return updateCancelled()
            if (received != expectedBytes) {
                return updateError("The update file was incomplete. Try again.")
            }
            val actual = digest.digest().joinToString("") { byte ->
                "%02x".format(byte)
            }
            if (actual != expectedSha) {
                return updateError(
                    "The update failed its checksum check and was deleted.",
                )
            }
            if (target.exists()) target.delete()
            if (!partFile.renameTo(target)) {
                return updateError("Sift could not save the update file.")
            }
            sendUpdateProgress(download.id, expectedBytes, expectedBytes)
            return mapOf(
                "ok" to true,
                "path" to target.absolutePath,
                "bytes" to received,
            )
        } catch (error: Exception) {
            if (download.cancelled) return updateCancelled()
            Log.w(TAG, "Update download failed", error)
            return updateError(
                "The update did not download. Check your connection and try again.",
            )
        } finally {
            try {
                download.connection?.disconnect()
            } catch (_: Exception) {
            }
            download.connection = null
            try {
                if (part?.exists() == true) part.delete()
            } catch (_: Exception) {
            }
        }
    }

    private fun cancelUpdate(id: String?) {
        val download = activeUpdate ?: return
        if (id != null && id != download.id) return
        download.cancel()
        if (activeUpdate === download) activeUpdate = null
    }

    private fun sendUpdateProgress(id: String, received: Long, total: Long) {
        val payload = mapOf("id" to id, "received" to received, "total" to total)
        mainHandler.post {
            try {
                channel?.invokeMethod("updateProgress", payload)
            } catch (_: Exception) {
            }
        }
    }

    private fun updateCancelled(): Map<String, Any?> =
        mapOf("ok" to false, "cancelled" to true)

    private fun updateError(message: String): Map<String, Any?> =
        mapOf("ok" to false, "error" to message)

    private fun isAllowedUpdateUri(uri: URI, serviceHost: String?): Boolean {
        if (!uri.scheme.equals("https", ignoreCase = true)) return false
        if (uri.userInfo != null) return false
        if (uri.port != -1 && uri.port != 443) return false
        val host = uri.host?.lowercase() ?: return false
        if (!serviceHost.isNullOrBlank() &&
            host == serviceHost.lowercase()
        ) {
            return true
        }
        if (host == "github.com") return true
        return host.endsWith(".githubusercontent.com")
    }

    private fun sanitizeApkName(input: String): String {
        val base = input
            .replace(Regex("[^A-Za-z0-9._-]"), "-")
            .trim('-', '.')
            .take(80)
            .ifBlank { "Sift-update" }
        return if (base.endsWith(".apk", ignoreCase = true)) base else "$base.apk"
    }

    private fun installUpdate(path: String?): Map<String, Any?> {
        if (path.isNullOrBlank()) {
            return updateError("The downloaded update is missing.")
        }
        val root = File(cacheDir, "updates").canonicalFile
        val file = try {
            File(path).canonicalFile
        } catch (_: Exception) {
            return updateError("The downloaded update is missing.")
        }
        if (!file.path.startsWith(root.path + File.separator) ||
            !file.isFile ||
            file.length() <= 0
        ) {
            return updateError("The downloaded update is missing.")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            return mapOf(
                "ok" to false,
                "needsPermission" to true,
                "error" to "Allow Sift to install updates, then try again.",
            )
        }
        return try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val install = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_ACTIVITY_NEW_TASK,
                )
            }
            startActivity(install)
            mapOf("ok" to true)
        } catch (error: Exception) {
            Log.w(TAG, "Could not open the package installer", error)
            updateError("Android did not open the installer.")
        }
    }

    private fun openInstallSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null),
            )
        }.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            openAppSettings()
        }
    }

    private fun setSecureScreen(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun openAppSettings() {
        val settings = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(settings)
        } catch (_: ActivityNotFoundException) {
            // Some heavily modified builds omit the settings activity.
        }
    }
}
