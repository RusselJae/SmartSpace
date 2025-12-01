package com.example.smartspace_ar

import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.smartspace/ar_support"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // The channel exposes a tiny bridge so Dart can request the current ARCore status.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkArAvailability" -> result.success(resolveArAvailability())
                else -> result.notImplemented()
            }
        }
    }

    private fun resolveArAvailability(): Map<String, Any> {
        // Query ARCore for the most recent availability without forcing a download.
        val availability = ArCoreApk.getInstance().checkAvailability(this)

        val isInstallable =
            availability == ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED ||
                availability == ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD
        val isInstalled = availability == ArCoreApk.Availability.SUPPORTED_INSTALLED
        val isSupported = isInstalled || isInstallable
        val isUnavailable = when (availability) {
            ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE,
            ArCoreApk.Availability.UNKNOWN_ERROR,
            ArCoreApk.Availability.UNKNOWN_CHECKING,
            ArCoreApk.Availability.UNKNOWN_TIMED_OUT -> true
            else -> false
        }

        return mapOf(
            "availability" to availability.name,
            "isSupported" to isSupported,
            "isInstalled" to isInstalled,
            "needsInstall" to isInstallable,
            "isUnavailable" to isUnavailable
        )
    }
}
