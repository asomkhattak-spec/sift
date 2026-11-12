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
import android.provider.Settings
import android.view.WindowManager
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "io.github.asomkhattak.sift/native"
        private const val DOWNLOAD_PERMISSION_REQUEST = 4701
        private val WEB_SCHEMES = setOf("http", "https")
        private val EXTERNAL_SCHEMES = setOf("http", "https", "mailto", "tel", "sms")
    }

    private var channel: MethodChannel? = null
    private var pendingIntent: Map<String, Any?>? = null
    private var pendingDownload: Map<String, Any?>? = null

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
