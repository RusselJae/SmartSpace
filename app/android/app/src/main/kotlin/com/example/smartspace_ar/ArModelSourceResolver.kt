package com.example.smartspace_ar

import android.content.Context
import android.net.Uri
import android.util.Log
import io.flutter.FlutterInjector
import java.io.File
import java.security.MessageDigest

/**
 * Resolves Flutter asset paths, local files, and remote URLs into something
 * SceneView's [io.github.sceneview.loaders.ModelLoader] can open.
 */
object ArModelSourceResolver {

    private const val TAG = "ArModelSourceResolver"

    /**
     * Returns a loadable source string: http(s) URL or absolute filesystem path.
     */
    fun resolve(context: Context, raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null

        when {
            trimmed.startsWith("http://", ignoreCase = true) ||
                trimmed.startsWith("https://", ignoreCase = true) -> return trimmed

            trimmed.startsWith("file://", ignoreCase = true) -> {
                val path = Uri.parse(trimmed).path ?: return null
                return if (File(path).exists()) path else null
            }

            trimmed.startsWith("/") && File(trimmed).exists() -> return trimmed

            trimmed.startsWith("assets/") -> return copyFlutterAssetToCache(context, trimmed)

            !trimmed.contains("://") && File(trimmed).exists() -> return trimmed
        }

        // Bare filename from older DB rows — try under Flutter assets/models/.
        if (!trimmed.contains('/')) {
            return copyFlutterAssetToCache(context, "assets/models/$trimmed")
        }

        Log.w(TAG, "Unrecognized model source: $trimmed")
        return null
    }

    private fun copyFlutterAssetToCache(context: Context, flutterAssetPath: String): String? {
        return try {
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) {
                loader.startInitialization(context.applicationContext)
                loader.ensureInitializationComplete(context.applicationContext, null)
            }

            val lookupKey = loader.getLookupKeyForAsset(flutterAssetPath)
            val cacheDir = File(context.cacheDir, "ar_model_cache").apply { mkdirs() }
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(flutterAssetPath.toByteArray())
                .joinToString("") { "%02x".format(it) }
                .take(16)
            val ext = flutterAssetPath.substringAfterLast('.', "glb")
            val outFile = File(cacheDir, "$digest.$ext")

            if (!outFile.exists() || outFile.length() == 0L) {
                context.assets.open(lookupKey).use { input ->
                    outFile.outputStream().use { output -> input.copyTo(output) }
                }
            }

            outFile.absolutePath
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to copy Flutter asset $flutterAssetPath", t)
            null
        }
    }
}
