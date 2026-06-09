package com.example.smartspace_ar

import io.github.sceneview.math.Position
import io.github.sceneview.math.Rotation
import io.github.sceneview.math.Scale
import io.github.sceneview.model.ModelInstance
import io.github.sceneview.node.ModelNode

/**
 * Wrapper around [ModelNode] for AR placement:
 * - Scale clamping (0.3×–4×)
 * - Yaw-only rotation
 * - Idempotent floor seating (safe to call after every scale change)
 * - Shadow casting + contact shadow at the model base
 */
class YawLimitedModelNode(
    modelInstance: ModelInstance
) : ModelNode(
    modelInstance = modelInstance,
    autoAnimate = false,
) {

    /**
     * Places the bounding-box bottom on the anchor point.
     *
     * Uses absolute Y (not [centerOrigin], which accumulates with `+=` and
     * pushes the mesh underground after scale / re-anchor calls).
     */
    fun seatOnFloorAnchor() {
        val center = boundingBox.center
        val half = boundingBox.halfExtent
        val bottomLocalY = center[1] - half[1]
        if (!bottomLocalY.isFinite()) return
        val yOffset = -bottomLocalY * scale.y
        if (!yOffset.isFinite()) return
        position = Position(position.x, yOffset, position.z)
    }

    /** Enable AR shadows without re-running floor seating (call [seatOnFloorAnchor] after scale). */
    fun configureArShadows() {
        try {
            isShadowCaster = true
            isShadowReceiver = false
            setScreenSpaceContactShadows(true)
        } catch (_: Throwable) {
        }
    }

    private var lastPosition: Position? = null
    private var lastStableRotation: Rotation? = null

    override fun onTransformChanged() {
        val currentScale = scale
        val clampedScale = Scale(
            x = currentScale.x.coerceIn(0.3f, 4.0f),
            y = currentScale.y.coerceIn(0.3f, 4.0f),
            z = currentScale.z.coerceIn(0.3f, 4.0f)
        )
        if (clampedScale != currentScale) {
            scale = clampedScale
        }

        val currentPosition = position
        val positionChanged = lastPosition != null && currentPosition != lastPosition
        lastPosition = currentPosition

        if (positionChanged) {
            lastStableRotation?.let { stable ->
                if (rotation != stable) {
                    rotation = stable
                }
            }
            super.onTransformChanged()
            return
        } else {
            val currentRotation = rotation
            val yawOnly = Rotation(x = 0.0f, y = currentRotation.y, z = 0.0f)
            if (yawOnly != currentRotation) {
                rotation = yawOnly
            }
            lastStableRotation = yawOnly
        }

        super.onTransformChanged()
    }
}
