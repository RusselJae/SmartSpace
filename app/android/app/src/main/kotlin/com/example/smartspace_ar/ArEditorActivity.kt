package com.example.smartspace_ar

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ar.core.Config
import com.google.ar.core.Session
import io.github.sceneview.ar.ARSceneView

/**
 * ###########################################################################
 * ## ArEditorActivity                                                       ##
 * ###########################################################################
 *
 * Very small native AR editor shell.
 *
 * IMPORTANT (current state):
 * - This Activity does *not* yet host a real ARCore surface. Instead, it
 *   provides a minimal, safe container that is fully wired to Flutter via
 *   `MainActivity` and the `com.smartspace/ar_editor` MethodChannel.
 * - The central `FrameLayout` is intentionally a placeholder so that the app
 *   compiles and runs without pulling in heavy native AR dependencies yet.
 * - Once you're ready to commit to a specific AR renderer (e.g. SceneView),
 *   that view can be embedded into the `arContainer` without changing the
 *   Flutter integration code.
 *
 * Flow:
 * - Flutter calls "openEditor" on `com.smartspace/ar_editor`.
 * - `MainActivity` starts this Activity, passing model + dimension extras.
 * - We:
 *     - Read the furniture model + real‑world dimensions from the Intent.
 *     - Build a simple full‑screen UI with a top bar and bottom controls.
 *     - Reserve the middle area (`arContainer`) for the eventual AR surface.
 */
class ArEditorActivity : Activity() {

    companion object {
        // Simple request code for camera permission prompts.
        private const val CAMERA_PERMISSION_REQUEST = 1001
    }

    // Values passed in from Flutter via the starting Intent.
    private var modelSrc: String? = null
    private var altText: String? = null
    private var realWidthMeters: Double? = null
    private var realHeightMeters: Double? = null
    private var realDepthMeters: Double? = null
    private var modelBaseScale: Double = 1.0

    // Native AR view powered by SceneView. We keep usage deliberately minimal
    // so that the Activity compiles cleanly while we iterate on behaviour.
    private lateinit var arSceneView: ARSceneView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // --------------------------------------------------------------------
        // 1. Read parameters from the launching Intent.
        // --------------------------------------------------------------------
        //
        // These are forwarded from Flutter so the eventual AR engine can
        // compute true-to-scale dimensions for the 3D model.
        intent.extras?.let { extras ->
            modelSrc = extras.getString("modelSrc")
            altText = extras.getString("altText")
            realWidthMeters = extras.getDoubleOrNull("realWidthMeters")
            realHeightMeters = extras.getDoubleOrNull("realHeightMeters")
            realDepthMeters = extras.getDoubleOrNull("realDepthMeters")
            modelBaseScale = extras.getDoubleOrNull("modelBaseScale") ?: 1.0
        }

        // --------------------------------------------------------------------
        // 2. Build an ultra-simple UI programmatically.
        // --------------------------------------------------------------------
        //
        // We avoid XML for now to keep everything in a single file while the
        // AR internals are still being prototyped.
        //
        // Layout:
        // - Root: vertical LinearLayout.
        // - Top: title bar with close button.
        // - Middle: FrameLayout placeholder where the AR view will live.
        // - Bottom: very simple control strip (scale +/- and rotate +/-).
        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFF000000.toInt())
        }

        // Simple top bar with title + close button.
        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(24, 24, 24, 16)
            setBackgroundColor(0xFF111111.toInt())
            elevation = 4f
        }

        val titleView = TextView(this).apply {
            text = altText ?: "AR Editor"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 18f
        }

        val closeButton = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setBackgroundColor(0x00000000)
            contentDescription = "Close AR Editor"
            setOnClickListener { finish() }
        }

        topBar.addView(
            titleView,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        )
        topBar.addView(
            closeButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        // Placeholder container where the AR surface will be attached later.
        val arContainer = FrameLayout(this).apply {
            id = View.generateViewId()
            setBackgroundColor(0xFF000000.toInt())
        }

        val arContainerParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            0,
            1f
        )

        // Bottom control strip with extremely simple controls.
        val bottomControls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(16, 12, 16, 24)
            setBackgroundColor(0xFF111111.toInt())
            weightSum = 4f
        }

        fun makeControlButton(iconRes: Int, description: String): ImageButton {
            return ImageButton(this).apply {
                setImageResource(iconRes)
                setBackgroundColor(0xFF222222.toInt())
                contentDescription = description
                setColorFilter(0xFFFFFFFF.toInt())
                // Click handlers are wired as no-ops for now; once the AR
                // engine is added, these will update the model's transform.
            }
        }

        val scaleDownButton = makeControlButton(
            android.R.drawable.ic_media_previous,
            "Scale down"
        )
        val scaleUpButton = makeControlButton(
            android.R.drawable.ic_media_next,
            "Scale up"
        )
        val rotateLeftButton = makeControlButton(
            android.R.drawable.ic_media_rew,
            "Rotate left"
        )
        val rotateRightButton = makeControlButton(
            android.R.drawable.ic_media_ff,
            "Rotate right"
        )

        val buttonParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
            marginStart = 4
            marginEnd = 4
        }

        bottomControls.addView(scaleDownButton, buttonParams)
        bottomControls.addView(scaleUpButton, buttonParams)
        bottomControls.addView(rotateLeftButton, buttonParams)
        bottomControls.addView(rotateRightButton, buttonParams)

        // Assemble the layout.
        rootLayout.addView(
            topBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )
        rootLayout.addView(arContainer, arContainerParams)
        rootLayout.addView(
            bottomControls,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        // --------------------------------------------------------------------
        // 3. Attach a real ARSceneView into the placeholder and configure AR.
        // --------------------------------------------------------------------
        //
        // SceneView owns the underlying ARCore Session for us. We provide a
        // lightweight configuration lambda that enables depth (when possible),
        // instant placement and HDR-based light estimation. This should be
        // enough to get a live camera feed + plane detection on supported
        // devices, assuming Play Services for AR is installed.
        arSceneView = ARSceneView(this).apply {
            sessionConfiguration = { session: Session, config: Config ->
                // Depth: try automatic, fall back to disabled on unsupported devices.
                config.depthMode =
                    if (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                        Config.DepthMode.AUTOMATIC
                    } else {
                        Config.DepthMode.DISABLED
                    }

                // Enable more forgiving instant placement so users can place
                // furniture even before full plane tracking is stable.
                config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP

                // Use ARCore's environmental HDR light estimation so the model
                // feels grounded in the real room lighting.
                config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
            }
        }
        arContainer.addView(
          arSceneView,
          FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
          )
        )

        setContentView(rootLayout)

        // Bottom buttons currently act as visual affordances only. Once model
        // loading is in place, their onClick handlers can update transforms.
        scaleDownButton.setOnClickListener { /* TODO: hook into AR scale */ }
        scaleUpButton.setOnClickListener { /* TODO: hook into AR scale */ }
        rotateLeftButton.setOnClickListener { /* TODO: hook into AR rotation */ }
        rotateRightButton.setOnClickListener { /* TODO: hook into AR rotation */ }

        // --------------------------------------------------------------------
        // 4. Camera permission check (basic handling).
        // --------------------------------------------------------------------
        //
        // This keeps the Activity from crashing on devices where the camera
        // permission hasn't been granted yet.
        ensureCameraPermission()
    }

    /**
     * Basic camera permission helper. This keeps the Activity from crashing
     * on devices where the permission has not yet been granted.
     */
    private fun ensureCameraPermission() {
        val needed = Manifest.permission.CAMERA
        if (ContextCompat.checkSelfPermission(this, needed) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        ActivityCompat.requestPermissions(this, arrayOf(needed), CAMERA_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            // For now we simply ignore the result. Once a real AR surface is
            // integrated this is where you would either start the AR session
            // or show a helpful error UI.
        }
    }

}

// Small extension helpers to safely read nullable doubles from Bundle extras
// without crashing when keys are missing or of a different type.
private fun Bundle.getDoubleOrNull(key: String): Double? {
    return if (containsKey(key)) {
        try {
            getDouble(key)
        } catch (_: Exception) {
            null
        }
    } else {
        null
    }
}

