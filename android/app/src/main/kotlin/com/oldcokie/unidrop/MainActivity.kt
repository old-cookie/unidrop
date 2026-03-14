package com.oldcokie.unidrop

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.oldcokie.unidrop/browser"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
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
    }
}