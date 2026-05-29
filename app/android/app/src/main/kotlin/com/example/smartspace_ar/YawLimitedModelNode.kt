package com.example.smartspace_ar

import io.github.sceneview.math.Position
import io.github.sceneview.math.Rotation
import io.github.sceneview.math.Scale
import io.github.sceneview.model.ModelInstance
import io.github.sceneview.node.ModelNode

/**
 * Small wrapper around [ModelNode] that:
 *
 * - Clamps user scaling so the model never goes below 30% of its authored size
 *   (or above 4x, to keep things sane).
 * - Forces rotation to yaw (left/right) only so the model cannot be flipped
 *   upside‑down by gesture input.
 * - Preserves rotation while the user is only dragging position (SceneView can
 *   briefly inject tilt/roll during a move; resetting euler x/z causes flips).
 */
class YawLimitedModelNode(
    modelInstance: ModelInstance
) : ModelNode(modelInstance = modelInstance) {

    private var lastPosition: Position? = null
    private var lastStableRotation: Rotation? = null

    override fun onTransformChanged() {
        // Clamp scale so that the node never becomes comically tiny or huge.
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
            // Position drag: undo rotation noise only; never rewrite position here.
            lastStableRotation?.let { stable ->
                if (rotation != stable) {
                    rotation = stable
                }
            }
            super.onTransformChanged()
            return
        } else {
            // Pinch / rotate (or first frame): keep yaw only, remember stable facing.
            val currentRotation = rotation
            val yawOnly = Rotation(
                x = 0.0f,
                y = currentRotation.y,
                z = 0.0f
            )
            if (yawOnly != currentRotation) {
                rotation = yawOnly
            }
            lastStableRotation = yawOnly
        }

        super.onTransformChanged()
    }
}
