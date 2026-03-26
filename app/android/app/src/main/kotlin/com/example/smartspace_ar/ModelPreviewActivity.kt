package com.example.smartspace_ar

import android.os.Bundle
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import io.github.sceneview.SceneView
import io.github.sceneview.math.Position
import io.github.sceneview.math.Rotation
import io.github.sceneview.math.Scale
import io.github.sceneview.model.ModelInstance

/**
 * Full-screen model preview with rotate gesture support.
 *
 * This is the native equivalent of the "product detail card" model viewer:
 * users can drag to rotate and pinch to scale (simple, but feels familiar).
 */
class ModelPreviewActivity : ComponentActivity() {

    private lateinit var sceneView: SceneView
    private var modelNode: YawLimitedModelNode? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Let content draw edge-to-edge.
        WindowCompat.setDecorFitsSystemWindows(window, false)

        sceneView = SceneView(this).apply {
            // Default background is fine; keep it subtle so the model is the focus.
            // (SceneView itself handles camera + lighting internally.)
        }

        val root = FrameLayout(this).apply {
            addView(
                sceneView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
        }

        setContentView(root)

        val modelSrc = intent.getStringExtra("modelSrc")
        val altText = intent.getStringExtra("altText") ?: "Model preview"

        if (modelSrc.isNullOrBlank()) {
            Toast.makeText(this, "No model available", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        // Keep consistent with ArEditorActivity: only treat http(s) as directly loadable.
        val looksLikeHttp = modelSrc.startsWith("http://") || modelSrc.startsWith("https://")
        if (!looksLikeHttp) {
            Toast.makeText(this, "Preview not supported for this model path", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        sceneView.modelLoader.loadModelInstanceAsync(modelSrc) { instance: ModelInstance? ->
            if (instance == null) return@loadModelInstanceAsync
            runOnUiThread {
                if (isFinishing) return@runOnUiThread
                attachModel(instance)
            }
        }
    }

    private fun attachModel(instance: ModelInstance) {
        // Remove any previous node.
        modelNode?.let { existing ->
            sceneView.removeChildNode(existing)
        }

        val baseScale = 1.0f
        val node = YawLimitedModelNode(modelInstance = instance).apply {
            // Keep preview interaction constrained:
            // - Fixed placement in the center
            // - Rotation only (yaw/left-right)
            // - No drag / no pinch-zoom
            isEditable = true
            isPositionEditable = false
            isRotationEditable = true
            isScaleEditable = false
            editableScaleRange = 1.0f..1.0f

            // Put the model in front of the camera so it is immediately visible.
            position = Position(x = 0f, y = -0.2f, z = -3.5f)
            rotation = Rotation(x = 0f, y = 0f, z = 0f)
            scale = Scale(baseScale, baseScale, baseScale)
        }

        sceneView.addChildNode(node)
        modelNode = node
    }
}

