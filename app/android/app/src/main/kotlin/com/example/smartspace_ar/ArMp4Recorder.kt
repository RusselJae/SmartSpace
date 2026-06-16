package com.example.smartspace_ar

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.view.Surface
import java.io.File

/**
 * Encodes AR frame bitmaps (from [android.view.PixelCopy]) into an MP4.
 * Uses capture timestamps so playback matches real recording duration.
 */
object ArMp4Recorder {

    data class TimedFrame(
        val bitmap: Bitmap,
        /** Microseconds since recording start. */
        val presentationTimeUs: Long,
    )

    private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
    private const val IFRAME_INTERVAL = 1
    /** 720p @ ~10 fps — enough for AR clips without huge files. */
    private const val BITRATE = 3_500_000
    private const val TIMEOUT_US = 10_000L

    fun saveFramesAsMp4(context: Context, frames: List<TimedFrame>): Uri? {
        if (frames.isEmpty()) return null
        val (width, height) = ArCaptureScaler.targetSize(
            frames.first().bitmap.width,
            frames.first().bitmap.height,
        )
        if (width <= 0 || height <= 0) return null

        val sorted = frames.sortedBy { it.presentationTimeUs }
        val basePts = sorted.first().presentationTimeUs
        val normalizedPts = sorted.map { (it.presentationTimeUs - basePts).coerceAtLeast(0L) }

        val cacheFile = File(context.cacheDir, "ar_clip_${System.currentTimeMillis()}.mp4")
        var muxer: MediaMuxer? = null
        var encoder: MediaCodec? = null
        var inputSurface: Surface? = null
        try {
            val durationUs = normalizedPts.lastOrNull()?.coerceAtLeast(1L) ?: 1L
            val nominalFps = ((sorted.size * 1_000_000.0) / durationUs)
                .coerceIn(4.0, 30.0)
                .toInt()

            val format = MediaFormat.createVideoFormat(MIME, width, height).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                )
                setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
                setInteger(MediaFormat.KEY_FRAME_RATE, nominalFps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, IFRAME_INTERVAL)
            }

            encoder = MediaCodec.createEncoderByType(MIME)
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = encoder.createInputSurface()
            encoder.start()

            muxer = MediaMuxer(cacheFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            var trackIndex = -1
            var muxerStarted = false
            val bufferInfo = MediaCodec.BufferInfo()
            var outputPtsIndex = 0

            for (frame in sorted) {
                val bitmap = frame.bitmap
                val scaled = ArCaptureScaler.scaleToMax720p(bitmap)
                drawBitmapToEncoderSurface(inputSurface!!, scaled)
                if (scaled !== bitmap) scaled.recycle()

                val drain = drainEncoder(
                    encoder = encoder,
                    muxer = muxer,
                    bufferInfo = bufferInfo,
                    trackIndex = trackIndex,
                    muxerStarted = muxerStarted,
                    endOfStream = false,
                    presentationTimeUs = normalizedPts.getOrNull(outputPtsIndex),
                )
                trackIndex = drain.trackIndex
                muxerStarted = drain.muxerStarted
                if (drain.wroteSample) {
                    outputPtsIndex++
                }
            }

            encoder.signalEndOfInputStream()
            drainEncoder(
                encoder = encoder,
                muxer = muxer,
                bufferInfo = bufferInfo,
                trackIndex = trackIndex,
                muxerStarted = muxerStarted,
                endOfStream = true,
                presentationTimeUs = null,
            )

            if (muxerStarted) {
                muxer.stop()
            }
            muxer.release()
            muxer = null
            encoder.stop()
            encoder.release()
            encoder = null
            inputSurface.release()
            inputSurface = null

            return copyToMediaStore(context, cacheFile)
        } catch (t: Throwable) {
            try {
                muxer?.release()
            } catch (_: Throwable) {
            }
            try {
                encoder?.release()
            } catch (_: Throwable) {
            }
            try {
                inputSurface?.release()
            } catch (_: Throwable) {
            }
            cacheFile.delete()
            return null
        }
    }

    private data class DrainState(
        val trackIndex: Int,
        val muxerStarted: Boolean,
        val wroteSample: Boolean = false,
    )

    private fun drawBitmapToEncoderSurface(surface: Surface, bitmap: Bitmap) {
        val canvas = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            surface.lockHardwareCanvas()
        } else {
            @Suppress("DEPRECATION")
            surface.lockCanvas(null)
        }
        try {
            canvas.drawColor(Color.BLACK)
            canvas.drawBitmap(bitmap, 0f, 0f, null)
        } finally {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                surface.unlockCanvasAndPost(canvas)
            } else {
                @Suppress("DEPRECATION")
                surface.unlockCanvasAndPost(canvas)
            }
        }
    }

    private fun drainEncoder(
        encoder: MediaCodec,
        muxer: MediaMuxer,
        bufferInfo: MediaCodec.BufferInfo,
        trackIndex: Int,
        muxerStarted: Boolean,
        endOfStream: Boolean,
        presentationTimeUs: Long?,
    ): DrainState {
        var currentTrack = trackIndex
        var started = muxerStarted
        var wroteSample = false
        while (true) {
            val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
            when {
                outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (endOfStream) continue else return DrainState(currentTrack, started, wroteSample)
                }
                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (started) return DrainState(currentTrack, started, wroteSample)
                    currentTrack = muxer.addTrack(encoder.outputFormat)
                    muxer.start()
                    started = true
                }
                outputIndex >= 0 -> {
                    if (!started) {
                        encoder.releaseOutputBuffer(outputIndex, false)
                        continue
                    }
                    val encoded = encoder.getOutputBuffer(outputIndex)
                    if (encoded != null && bufferInfo.size > 0) {
                        if (presentationTimeUs != null) {
                            bufferInfo.presentationTimeUs = presentationTimeUs
                        }
                        encoded.position(bufferInfo.offset)
                        encoded.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(currentTrack, encoded, bufferInfo)
                        wroteSample = true
                    }
                    encoder.releaseOutputBuffer(outputIndex, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        return DrainState(currentTrack, started, wroteSample)
                    }
                }
            }
        }
    }

    private fun copyToMediaStore(context: Context, file: File): Uri? {
        val filename = "smartspace_ar_${System.currentTimeMillis()}.mp4"
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, filename)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/SmartSpace")
            }
        }
        val uri = context.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: return null
        context.contentResolver.openOutputStream(uri).use { out ->
            if (out == null) return null
            file.inputStream().use { input -> input.copyTo(out) }
        }
        file.delete()
        return uri
    }
}
