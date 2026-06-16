package com.example.smartspace_ar

import android.graphics.Bitmap
import kotlin.math.min

/**
 * Downscales AR frame bitmaps so exported video stays at or below 720p.
 * Width is also capped at 1280 to match standard 720p bounds.
 */
object ArCaptureScaler {

    const val MAX_VIDEO_HEIGHT = 720
    const val MAX_VIDEO_WIDTH = 1280

    /** Output dimensions for a source frame (even width/height for the encoder). */
    fun targetSize(srcW: Int, srcH: Int): Pair<Int, Int> {
        if (srcW <= 0 || srcH <= 0) return 0 to 0
        val scale = min(
            min(MAX_VIDEO_WIDTH.toFloat() / srcW, MAX_VIDEO_HEIGHT.toFloat() / srcH),
            1f,
        )
        val dstW = (srcW * scale).toInt().coerceAtLeast(2) and 0xFFFE
        val dstH = (srcH * scale).toInt().coerceAtLeast(2) and 0xFFFE
        return dstW to dstH
    }

    /** Returns [source] unchanged when it already fits within the 720p cap. */
    fun scaleToMax720p(source: Bitmap): Bitmap {
        val (dstW, dstH) = targetSize(source.width, source.height)
        if (dstW <= 0 || dstH <= 0) return source
        if (dstW == source.width && dstH == source.height) return source
        return Bitmap.createScaledBitmap(source, dstW, dstH, true)
    }
}
