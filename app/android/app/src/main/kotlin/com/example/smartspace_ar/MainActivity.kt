package com.example.smartspace_ar

import android.content.Intent
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val supportChannelName = "com.smartspace/ar_support"
    private val editorChannelName = "com.smartspace/ar_editor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // --------------------------------------------------------------------
        // Channel 1: AR support / availability checks (existing behavior).
        // --------------------------------------------------------------------
        //
        // This is used by the Flutter layer to decide whether to show ARCore /
        // Scene Viewer / WebXR entry points. Kept exactly as before so there
        // is no behavioral regression.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, supportChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkArAvailability" -> result.success(resolveArAvailability())
                    else -> result.notImplemented()
                }
            }

        // --------------------------------------------------------------------
        // Channel 2: AR editor entrypoint.
        // --------------------------------------------------------------------
        //
        // This tiny bridge lets Flutter request a native AR editor screen
        // implemented in Kotlin (`ArEditorActivity`). The activity itself is
        // currently a simple UI shell; the heavy ARCore work will be added
        // incrementally without changing the Dart side.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, editorChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openEditor" -> {
                        openArEditor(call.arguments)
                        result.success(null)
                    }
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

    /**
     * Launches the lightweight native AR editor Activity.
     *
     * The `args` object comes from Flutter and is expected to be a Map-like
     * structure with the following optional keys:
     * - modelSrc: String (GLB path or URL)
     * - altText: String (for future accessibility copy)
     * - realWidthMeters / realHeightMeters / realDepthMeters: Double
     * - modelBaseScale: Double
     *
     * We forward these into the Activity via Intent extras so the eventual
     * ARCore renderer can compute true-to-scale sizing.
     */
    private fun openArEditor(args: Any?) {
        val context = this
        val intent = Intent(context, ArEditorActivity::class.java)

        if (args is Map<*, *>) {
            (args["modelSrc"] as? String)?.let { intent.putExtra("modelSrc", it) }
            (args["altText"] as? String)?.let { intent.putExtra("altText", it) }

            (args["realWidthMeters"] as? Number)?.toDouble()?.let {
                intent.putExtra("realWidthMeters", it)
            }
            (args["realHeightMeters"] as? Number)?.toDouble()?.let {
                intent.putExtra("realHeightMeters", it)
            }
            (args["realDepthMeters"] as? Number)?.toDouble()?.let {
                intent.putExtra("realDepthMeters", it)
            }
            (args["modelBaseScale"] as? Number)?.toDouble()?.let {
                intent.putExtra("modelBaseScale", it)
            }

            // Option A: variant list for in-place model swapping.
            (args["variantProductsJson"] as? String)?.let { intent.putExtra("variantProductsJson", it) }
            (args["initialProductId"] as? String)?.let { intent.putExtra("initialProductId", it) }
        }

        startActivity(intent)
    }
}
