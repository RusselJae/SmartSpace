package com.example.smartspace_ar

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
 */
class YawLimitedModelNode(
    modelInstance: ModelInstance
) : ModelNode(modelInstance = modelInstance) {

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

        // Project any rotation back onto the Y axis so that the model can only
        // spin left/right and never roll over or tilt forward/backward.
        val currentRotation = rotation
        val yawOnly = Rotation(
            x = 0.0f,
            y = currentRotation.y,
            z = 0.0f
        )
        if (yawOnly != currentRotation) {
            rotation = yawOnly
        }

        super.onTransformChanged()
    }
}

