package com.example.smartspace_ar

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View

/**
 * Scene Viewer–style reticle: outer ring + inner dot.
 * Position on screen via [translationX]/[translationY] on this view (parent is full-screen).
 * [isFloorReady] brightens the ring when anchored on a detected floor.
 */
class PlacementReticleView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private val density = resources.displayMetrics.density

    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.WHITE
        strokeWidth = 2f * density
    }

    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
    }

    /** True when a horizontal plane is hit-tested under the screen center. */
    var isFloorReady: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            alpha = if (value) 1f else 0.42f
            invalidate()
        }

    init {
        alpha = 0.42f
        isClickable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val outerR = (minOf(width, height) / 2f) - ringPaint.strokeWidth
        canvas.drawCircle(cx, cy, outerR, ringPaint)
        dotPaint.alpha = if (isFloorReady) 220 else 110
        canvas.drawCircle(cx, cy, 4f * density, dotPaint)
    }
}
