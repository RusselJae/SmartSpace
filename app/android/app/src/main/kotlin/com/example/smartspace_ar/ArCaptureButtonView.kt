package com.example.smartspace_ar

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import kotlin.math.min
import kotlin.math.sin

/**
 * Unified AR shutter: tap for photo, hold for video.
 *
 * While recording, a lightweight canvas ring shows elapsed progress toward the
 * 30-second cap plus a subtle pulse — no layout animations, no GL work.
 */
class ArCaptureButtonView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    interface Listener {
        fun onPhotoTap()
        fun onVideoRecordStart()
        fun onVideoRecordStop()
    }

    /** Distinguish tap from hold without feeling sluggish. */
    private val holdThresholdMs = 280L

    private val density = resources.displayMetrics.density
    private val outerSizePx = (80f * density).toInt()
    private val buttonSizePx = (64f * density).toInt()

    private val holdHandler = Handler(Looper.getMainLooper())
    private var listener: Listener? = null

    private var isPointerDown = false
    private var holdActivated = false

    private var isRecording = false
    private var recordProgress = 0f

    private val ringView = RecordingRingView(context)
    private val shutterButton: ImageButton

    private val pulseRunnable = object : Runnable {
        override fun run() {
            if (!isRecording) return
            ringView.invalidate()
            holdHandler.postDelayed(this, PULSE_INTERVAL_MS)
        }
    }

    init {
        isClickable = true
        isFocusable = true

        addView(
            ringView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )

        shutterButton = ImageButton(context).apply {
            setImageResource(R.drawable.ic_ar_camera)
            setBackgroundResource(R.drawable.bg_ar_capture_shutter)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(
                (14f * density).toInt(),
                (14f * density).toInt(),
                (14f * density).toInt(),
                (14f * density).toInt(),
            )
            contentDescription = "Tap for photo, hold for video"
            isClickable = false
            isFocusable = false
        }
        addView(
            shutterButton,
            LayoutParams(buttonSizePx, buttonSizePx, android.view.Gravity.CENTER),
        )

        layoutParams = LayoutParams(outerSizePx, outerSizePx)
    }

    fun setListener(listener: Listener?) {
        this.listener = listener
    }

    /** Drive the progress arc (0..1) while video is recording. */
    fun setRecording(active: Boolean, progress: Float = 0f) {
        val wasRecording = isRecording
        isRecording = active
        recordProgress = progress.coerceIn(0f, 1f)
        ringView.invalidate()

        if (active && !wasRecording) {
            holdHandler.removeCallbacks(pulseRunnable)
            holdHandler.post(pulseRunnable)
        } else if (!active && wasRecording) {
            holdHandler.removeCallbacks(pulseRunnable)
            ringView.invalidate()
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                isPointerDown = true
                holdActivated = false
                parent?.requestDisallowInterceptTouchEvent(true)
                holdHandler.removeCallbacks(holdRunnable)
                holdHandler.postDelayed(holdRunnable, holdThresholdMs)
                return true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                isPointerDown = false
                parent?.requestDisallowInterceptTouchEvent(false)
                holdHandler.removeCallbacks(holdRunnable)

                if (holdActivated) {
                    holdActivated = false
                    listener?.onVideoRecordStop()
                } else {
                    listener?.onPhotoTap()
                }
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    private val holdRunnable = Runnable {
        if (!isPointerDown) return@Runnable
        holdActivated = true
        listener?.onVideoRecordStart()
    }

    /**
     * Draws the recording ring on a plain [View] — cheap invalidates only while recording.
     */
    private inner class RecordingRingView(context: Context) : View(context) {

        private val strokePx = 3.5f * density

        private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokePx
            color = Color.argb(90, 255, 255, 255)
        }

        private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokePx
            strokeCap = Paint.Cap.ROUND
            color = Color.argb(230, 255, 59, 48)
        }

        private val pulsePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokePx * 0.85f
            color = Color.argb(160, 255, 59, 48)
        }

        init {
            isClickable = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (!isRecording) return

            val cx = width / 2f
            val cy = height / 2f
            val maxR = min(width, height) / 2f - strokePx * 1.5f

            // Dim track — full circle behind the progress arc.
            canvas.drawCircle(cx, cy, maxR, trackPaint)

            // Elapsed progress toward the 30 s cap.
            if (recordProgress > 0.001f) {
                val sweep = 360f * recordProgress
                canvas.drawArc(
                    cx - maxR,
                    cy - maxR,
                    cx + maxR,
                    cy + maxR,
                    -90f,
                    sweep,
                    false,
                    progressPaint,
                )
            }

            // Soft pulse so "recording" is obvious even at the start of a clip.
            val pulse = 0.55f + 0.45f * sin(SystemClock.uptimeMillis() * 0.007).toFloat()
            pulsePaint.alpha = (pulse * 140).toInt().coerceIn(40, 180)
            val pulseR = maxR + strokePx * 0.35f
            canvas.drawCircle(cx, cy, pulseR, pulsePaint)
        }
    }

    companion object {
        /** ~12 fps pulse refresh — enough for a ring, light on the main thread. */
        private const val PULSE_INTERVAL_MS = 80L
    }
}
