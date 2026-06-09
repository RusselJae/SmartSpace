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

 * Encodes AR frame bitmaps (from [PixelCopy]) into an MP4 via a MediaCodec input

 * [Surface]. Avoids manual NV21/NV12 conversion, which often corrupts output.

 */

object ArMp4Recorder {



    private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC

    private const val IFRAME_INTERVAL = 1

    private const val BITRATE = 6_000_000

    private const val TIMEOUT_US = 10_000L



    fun saveFramesAsMp4(

        context: Context,

        frames: List<Bitmap>,

        fps: Int = 8,

    ): Uri? {

        if (frames.isEmpty()) return null

        val width = frames.first().width and 0xFFFE

        val height = frames.first().height and 0xFFFE

        if (width <= 0 || height <= 0) return null



        val cacheFile = File(context.cacheDir, "ar_clip_${System.currentTimeMillis()}.mp4")

        var muxer: MediaMuxer? = null

        var encoder: MediaCodec? = null

        var inputSurface: Surface? = null

        try {

            val format = MediaFormat.createVideoFormat(MIME, width, height).apply {

                setInteger(

                    MediaFormat.KEY_COLOR_FORMAT,

                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface

                )

                setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)

                setInteger(MediaFormat.KEY_FRAME_RATE, fps.coerceAtLeast(1))

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



            for (frame in frames) {

                val scaled = if (frame.width == width && frame.height == height) {

                    frame

                } else {

                    Bitmap.createScaledBitmap(frame, width, height, true)

                }

                drawBitmapToEncoderSurface(inputSurface!!, scaled)

                if (scaled !== frame) scaled.recycle()



                val drain = drainEncoder(

                    encoder = encoder,

                    muxer = muxer,

                    bufferInfo = bufferInfo,

                    trackIndex = trackIndex,

                    muxerStarted = muxerStarted,

                    endOfStream = false,

                )

                trackIndex = drain.trackIndex

                muxerStarted = drain.muxerStarted

            }



            encoder.signalEndOfInputStream()

            val finalDrain = drainEncoder(

                encoder = encoder,

                muxer = muxer,

                bufferInfo = bufferInfo,

                trackIndex = trackIndex,

                muxerStarted = muxerStarted,

                endOfStream = true,

            )

            trackIndex = finalDrain.trackIndex

            muxerStarted = finalDrain.muxerStarted



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



    private data class DrainState(val trackIndex: Int, val muxerStarted: Boolean)



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

    ): DrainState {

        var currentTrack = trackIndex

        var started = muxerStarted

        while (true) {

            val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)

            when {

                outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {

                    if (endOfStream) continue else return DrainState(currentTrack, started)

                }

                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {

                    if (started) return DrainState(currentTrack, started)

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

                        encoded.position(bufferInfo.offset)

                        encoded.limit(bufferInfo.offset + bufferInfo.size)

                        muxer.writeSampleData(currentTrack, encoded, bufferInfo)

                    }

                    encoder.releaseOutputBuffer(outputIndex, false)

                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {

                        return DrainState(currentTrack, started)

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


