package com.example.smartspace_ar

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Resolves Flutter asset paths, local files, and remote URLs for SceneView.
 *
 * Bundled GLBs are preferentially loaded from `flutter_assets/...` via
 * [android.content.res.AssetManager]. A disk cache copy is used only when
 * needed (e.g. alternate filename resolved).
 */
object ArModelSourceResolver {

    private const val TAG = "ArModelSourceResolver"

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    /** One copy per asset path at a time; avoids deleting a file another load is reading. */
    private val copyLocks = java.util.concurrent.ConcurrentHashMap<String, Any>()

    /**
     * SceneView's [io.github.sceneview.utils.FileLoader] opens bare paths via
     * [android.content.res.AssetManager]. Local GLBs must use a `file://` URI.
     */
    private fun toSceneViewLocalUri(file: File): String = Uri.fromFile(file).toString()

    fun resolveFast(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null

        when {
            trimmed.startsWith("http://", ignoreCase = true) ||
                trimmed.startsWith("https://", ignoreCase = true) -> return trimmed

            trimmed.startsWith("file://", ignoreCase = true) -> {
                val path = Uri.parse(trimmed).path ?: return null
                val file = File(path)
                return if (file.exists() && file.length() > 0L) trimmed else null
            }

            trimmed.startsWith("/") -> {
                val file = File(trimmed)
                return if (file.exists() && file.length() > 0L) toSceneViewLocalUri(file) else null
            }

            !trimmed.contains("://") -> {
                val file = File(trimmed)
                return if (file.exists() && file.length() > 0L) toSceneViewLocalUri(file) else null
            }
        }
        return null
    }

    fun resolveAsync(context: Context, raw: String, onResolved: (String?) -> Unit) {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            mainHandler.post { onResolved(null) }
            return
        }

        resolveFast(trimmed)?.let { fast ->
            mainHandler.post { onResolved(fast) }
            return
        }

        val assetPath = when {
            trimmed.startsWith("assets/") -> trimmed
            !trimmed.contains('/') -> "assets/models/$trimmed"
            else -> {
                Log.w(TAG, "Unrecognized model source: $trimmed")
                mainHandler.post { onResolved(null) }
                return
            }
        }

        val appContext = context.applicationContext
        ioExecutor.execute {
            val path = try {
                resolveBundledAssetPath(appContext, assetPath)
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to resolve Flutter asset $assetPath", t)
                null
            }
            if (path == null) {
                Log.e(TAG, "No bundled GLB found for requested path: $assetPath")
            } else {
                Log.d(TAG, "Resolved $assetPath -> $path")
            }
            mainHandler.post { onResolved(path) }
        }
    }

    /**
     * APK path for a pubspec asset, e.g. `assets/models/foo.glb` →
     * `flutter_assets/assets/models/foo.glb`.
     */
    private fun apkAssetPath(flutterAssetPath: String): String =
        "flutter_assets/$flutterAssetPath"

    /**
     * Tries the requested pubspec path plus common renames (e.g. `_compressed`
     * suffix after gltf-transform, typo fixes).
     */
    private fun buildAssetPathCandidates(flutterAssetPath: String): List<String> {
        val out = linkedSetOf(flutterAssetPath)
        if (flutterAssetPath.endsWith(".glb", ignoreCase = true)) {
            val withoutExt = flutterAssetPath.dropLast(4)
            if (!withoutExt.endsWith("_compressed", ignoreCase = true)) {
                out.add("$withoutExt" + "_compressed.glb")
            }
            if (withoutExt.contains("woode_6_drawer")) {
                out.add(withoutExt.replace("woode_6_drawer", "wooden_6_drawer") + "_compressed.glb")
                out.add(withoutExt.replace("woode_6_drawer", "wooden_6_drawer") + ".glb")
            }
        }
        return out.toList()
    }

    private fun assetExists(context: Context, apkPath: String): Boolean {
        return try {
            context.assets.open(apkPath).use { it.available() >= 0 }
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Prefer loading from the APK asset tree (SceneView → AssetManager).
     * Fall back to a stable `file://` cache copy when needed.
     */
    private fun resolveBundledAssetPath(context: Context, flutterAssetPath: String): String? {
        val candidates = buildAssetPathCandidates(flutterAssetPath)
        for (candidate in candidates) {
            val apkPath = apkAssetPath(candidate)
            if (assetExists(context, apkPath)) {
                return apkPath
            }
        }
        for (candidate in candidates) {
            copyFlutterAssetToCache(context, candidate)?.let { return it }
        }
        return null
    }

    private fun copyFlutterAssetToCache(context: Context, flutterAssetPath: String): String? {
        val lock = copyLocks.computeIfAbsent(flutterAssetPath) { Any() }
        synchronized(lock) {
            val cacheDir = File(context.cacheDir, "ar_model_cache").apply { mkdirs() }
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(flutterAssetPath.toByteArray())
                .joinToString("") { "%02x".format(it) }
                .take(16)
            val ext = flutterAssetPath.substringAfterLast('.', "glb")
            val outFile = File(cacheDir, "$digest.$ext")

            if (outFile.exists() && outFile.length() > 0L) {
                return toSceneViewLocalUri(outFile)
            }

            val apkPath = apkAssetPath(flutterAssetPath)
            val part = File("${outFile.path}.part")
            if (part.exists()) part.delete()

            try {
                context.assets.open(apkPath).use { input ->
                    part.outputStream().use { output ->
                        input.copyTo(output, bufferSize = 64 * 1024)
                    }
                }
            } catch (t: Throwable) {
                part.delete()
                Log.w(TAG, "Asset missing from APK: $apkPath (pubspec path: $flutterAssetPath)", t)
                return null
            }

            if (!part.renameTo(outFile)) {
                part.copyTo(outFile, overwrite = true)
                part.delete()
            }

            return if (outFile.exists() && outFile.length() > 0L) {
                toSceneViewLocalUri(outFile)
            } else {
                outFile.delete()
                null
            }
        }
    }
}
