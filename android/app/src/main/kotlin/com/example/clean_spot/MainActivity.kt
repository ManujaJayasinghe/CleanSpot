package com.example.clean_spot

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.clean_spot/maps"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasMapsApiKey" -> {
                    val key = readMapsApiKey()
                    result.success(key.isNotEmpty())
                }
                "getMapsApiKey" -> {
                    result.success(readMapsApiKey())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readMapsApiKey(): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(
                packageName,
                PackageManager.GET_META_DATA
            )
            val raw = appInfo.metaData
                ?.getString("com.google.android.geo.API_KEY")
                ?.trim()
                ?: ""
            if (raw.isEmpty() || raw.startsWith("\${")) "" else raw
        } catch (_: Exception) {
            ""
        }
    }
}
