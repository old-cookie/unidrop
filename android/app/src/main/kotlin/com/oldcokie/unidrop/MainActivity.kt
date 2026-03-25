package com.oldcokie.unidrop

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterFragmentActivity() {
    private val browserChannelName = "com.oldcokie.unidrop/browser"
    private val shareChannelName = "com.oldcokie.unidrop/share"

    private var shareChannel: MethodChannel? = null
    private var initialSharedMedia: List<Map<String, String>> = emptyList()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, browserChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url != null) {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                startActivity(intent)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("ACTIVITY_NOT_FOUND", "Browser not found", e.message)
                            }
                        } else {
                            result.error("INVALID_URL", "URL is null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
        shareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedMedia" -> result.success(initialSharedMedia)
                "clearInitialSharedMedia" -> {
                    initialSharedMedia = emptyList()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        initialSharedMedia = extractSharedMedia(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val sharedMedia = extractSharedMedia(intent)
        if (sharedMedia.isEmpty()) {
            return
        }

        if (shareChannel == null) {
            initialSharedMedia = sharedMedia
            return
        }

        shareChannel?.invokeMethod("onSharedMedia", sharedMedia)
    }

    private fun extractSharedMedia(intent: Intent?): List<Map<String, String>> {
        if (intent == null) return emptyList()

        val action = intent.action ?: return emptyList()
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return emptyList()
        }

        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            val uri = getIntentStream(intent)
            if (uri != null) {
                uris.add(uri)
            }
        } else {
            uris.addAll(getIntentStreams(intent))
        }

        if (uris.isEmpty()) return emptyList()

        val sharedMedia = mutableListOf<Map<String, String>>()
        for (uri in uris) {
            val mimeType = contentResolver.getType(uri) ?: intent.type ?: ""
            if (!mimeType.startsWith("image/") && !mimeType.startsWith("video/")) {
                continue
            }

            val originalName = queryDisplayName(uri)
                ?: "shared_${System.currentTimeMillis()}"

            val copiedFile = copySharedUriToCache(uri, originalName, mimeType)
            if (copiedFile != null) {
                sharedMedia.add(
                    mapOf(
                        "path" to copiedFile.absolutePath,
                        "fileName" to copiedFile.name,
                        "mimeType" to mimeType,
                    )
                )
            }
        }

        return sharedMedia
    }

    private fun getIntentStream(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
    }

    private fun getIntentStreams(intent: Intent): List<Uri> {
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }

        return result ?: emptyList()
    }

    private fun queryDisplayName(uri: Uri): String? {
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
        val cursor: Cursor = contentResolver.query(uri, projection, null, null, null) ?: return null
        cursor.use {
            if (!it.moveToFirst()) return null
            val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index < 0) return null
            return it.getString(index)
        }
    }

    private fun copySharedUriToCache(uri: Uri, originalName: String, mimeType: String): File? {
        return try {
            val sourceName = sanitizeFileName(originalName)
            val extension = sourceName.substringAfterLast('.', "")
            val resolvedExtension = if (extension.isNotEmpty()) {
                extension
            } else {
                MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?: "bin"
            }
            val baseName = sourceName.substringBeforeLast('.', sourceName)
            val timestamp = System.currentTimeMillis()
            val outputFile = File(cacheDir, "shared_${timestamp}_${baseName}.${resolvedExtension}")

            contentResolver.openInputStream(uri)?.use { input ->
                outputFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: return null

            outputFile
        } catch (_: IOException) {
            null
        } catch (_: SecurityException) {
            null
        }
    }

    private fun sanitizeFileName(fileName: String): String {
        return fileName
            .replace("\\", "_")
            .replace("/", "_")
            .replace(Regex("\\s+"), "_")
    }
}