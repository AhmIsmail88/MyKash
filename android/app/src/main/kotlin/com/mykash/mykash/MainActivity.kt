package com.mykash.mykash

import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes a stable hardware identity to Dart.
 *
 * `Settings.Secure.ANDROID_ID` survives reinstall and is unique per app
 * signature, so copying the app database to another phone does not copy the
 * entitlement with it. It is combined with build properties so a factory-reset
 * device still resolves to a different fingerprint.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "mykash/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "fingerprintRaw" -> {
                        val androidId = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID
                        ) ?: ""
                        result.success(
                            mapOf(
                                "androidId" to androidId,
                                "manufacturer" to Build.MANUFACTURER,
                                "model" to Build.MODEL,
                                "fingerprint" to Build.FINGERPRINT
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}