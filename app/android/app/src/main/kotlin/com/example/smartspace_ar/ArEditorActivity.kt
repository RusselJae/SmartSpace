package com.example.smartspace_ar

import android.Manifest
import android.app.AlertDialog
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.opengl.Matrix
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.PixelCopy
import android.text.TextUtils
import android.view.View
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import androidx.activity.ComponentActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.LightEstimate
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingFailureReason
import com.google.ar.core.TrackingState
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.ar.scene.PlaneRenderer
import io.github.sceneview.math.Position
import io.github.sceneview.math.Scale
import io.github.sceneview.math.Rotation
import io.github.sceneview.model.ModelInstance
import io.github.sceneview.model.renderableEntities
import android.os.SystemClock
import android.provider.MediaStore
import kotlin.math.roundToInt
import coil.load
import coil.transform.CircleCropTransformation

/**
 * ###########################################################################
 * ## ArEditorActivity                                                       ##
 * ###########################################################################
 *
 * Host Activity that displays a full‑screen [ARSceneView] with a minimal
 * overlay toolbar for AR controls and guidance.
 *
 * Flutter still launches this via the `com.smartspace/ar_editor` channel and
 * passes model metadata through the Intent. SceneView continues to provide
 * the primary gesture model (tap/drag/scale/rotate), while this Activity adds
 * a lightweight overlay with:
 * - Explicit scale controls (smaller / reset / bigger).
 * - Live labels for the current scale factor and approximate real‑world size.
 * - Short usage hints so first‑time users know how to interact.
 */
class ArEditorActivity : ComponentActivity() {

    companion object {
        // Simple request code for camera permission prompts.
        private const val CAMERA_PERMISSION_REQUEST = 1001
        /** Finger must move this far before we treat the gesture as a placement drag. */
        private const val DRAG_THRESHOLD_PX = 12f
        /** Avoid creating a new ARCore anchor on every MOVE event. */
        private const val REANCHOR_MIN_INTERVAL_MS = 80L
        /** Throttle contextual tip + reticle UI updates from [onSessionUpdated]. */
        private const val GUIDANCE_UI_INTERVAL_MS = 100L
        /** Require a tip key to persist this long before switching copy (reduces flicker). */
        private const val TIP_STABLE_MS = 350L
        /** [LightEstimate.pixelIntensity] below this is treated as "too dark". */
        private const val DARK_PIXEL_INTENSITY_THRESHOLD = 0.35f
        private const val DARK_FRAMES_BEFORE_TIP = 6
        /** Re-apply plane dot hiding — SceneView may re-enable after session resume. */
        private const val PLANE_HIDE_EVERY_N_FRAMES = 30
        /** Let ARCore depth stabilize before occlusion (avoids blank meshes on cold start). */
        private const val DEPTH_OCCLUSION_WARMUP_MS = 3_000L
    }

    // Values passed in from Flutter via the starting Intent. We continue to
    // read them so future SceneView‑level model loading can plug straight in.
    private var modelSrc: String? = null
    private var altText: String? = null
    private var realWidthMeters: Double? = null
    private var realHeightMeters: Double? = null
    private var realDepthMeters: Double? = null
    private var modelBaseScale: Double = 1.0
    private var initialProductId: String? = null

    // SharedPreferences state for persisting the user's last placement +
    // per-axis scale across leaving/re-entering the AR editor.
    private lateinit var prefs: SharedPreferences
    private var restoreIsPlaced: Boolean = false
    private var restoreHitXNorm: Float? = null
    private var restoreHitYNorm: Float? = null
    private var restoreScale: Scale? = null
    private var restoreYaw: Float? = null
    /** Local offset of the model under its anchor (drag); persisted across sessions. */
    private var restorePosition: Position? = null
    private var restorePlacementFailedFrames: Int = 0
    private var lastHitXNorm: Float? = null
    private var lastHitYNorm: Float? = null
    private var lastPersistedScale: Scale? = null
    private var lastPersistedYaw: Float? = null
    private var lastPersistedPosition: Position? = null
    private var lastPersistedVariantProductId: String? = null
    private var lastPersistAtMs: Long = 0L

    /**
     * Variant payload used for Option A (bottom-left picker).
     *
     * We keep this minimal (only what we need to swap the model + update the
     * scale/size overlay).
     */
    private data class VariantProduct(
        val productId: String,
        val name: String,
        val category: String,
        val modelSrc: String,
        /** First catalog image URL for circular thumbnails (optional). */
        val thumbnailUrl: String?,
        val realWidthMeters: Double?,
        val realHeightMeters: Double?,
        val realDepthMeters: Double?,
        val modelBaseScale: Double
    )

    private var variantProducts: List<VariantProduct> = emptyList()
    private var selectedVariantIndex: Int = 0
    private var variantSwapRequestId: Int = 0
    /** Prevents overlapping Filament loads that can OOM-crash on large GLBs. */
    private var variantLoadInProgress: Boolean = false
    private var pendingVariantIndex: Int? = null

    // Native AR view powered by SceneView. We keep usage deliberately minimal
    // so that the Activity compiles cleanly while we iterate on behaviour.
    private lateinit var arSceneView: ARSceneView

    // Cached 3D model instance loaded from [modelSrc]. We load this once and
    // reuse it for every tap‑to‑place operation so that placement feels snappy.
    private var modelInstance: ModelInstance? = null

    // Keep track of the currently placed anchor/model so we only auto-place
    // once when the AR session is ready.
    private var anchorNode: AnchorNode? = null
    private var modelNode: YawLimitedModelNode? = null

    // ------------------------------------------------------------------------
    // Lightweight overlay UI state
    // ------------------------------------------------------------------------
    //
    // We expose the current per‑axis scale factors and an approximate size
    // read‑out, plus guidance text, via a compact toolbar that floats above
    // the AR content. The toolbar is collapsible so it stays out of the way
    // once people are comfortable with the controls.
    /** Live W×H×D readout shown beneath the uniform scale slider. */
    private var dimensionsLabel: TextView? = null
    private var scaleFactorLabel: TextView? = null
    private var scaleOverlayWidthPx: Int = 0
    private var bottomControlsPanel: LinearLayout? = null
    private var placementControlsContainer: LinearLayout? = null
    private var captureControlsContainer: LinearLayout? = null
    private var scaleSeekBar: SeekBar? = null
    private var rotationSeekBar: SeekBar? = null
    private var isSyncingSlidersFromModel: Boolean = false
    private var placementProductNameLabel: TextView? = null
    private var captureProductNameLabel: TextView? = null
    private var placeModelButton: TextView? = null
    private var productThumbnailButton: ImageButton? = null
    private var photoModeButton: TextView? = null
    private var videoModeButton: TextView? = null
    private var captureActionButton: ImageButton? = null
    private var unlockButton: ImageButton? = null
    private var overlaysVisible: Boolean = true
    private var overlaysEyeButton: ImageButton? = null
    private var tipsHintButton: ImageButton? = null
    /** True after the user taps Place Model — shows capture controls instead. */
    private var isCaptureMode: Boolean = false
    /** Photo vs video capture while [isCaptureMode] is active. */
    private enum class CaptureKind { PHOTO, VIDEO }
    private var captureKind: CaptureKind = CaptureKind.PHOTO
    private var isVideoRecording: Boolean = false
    private val videoFrameBitmaps: MutableList<Bitmap> = mutableListOf()
    private var videoRecordHandler: Handler? = null
    private var videoRecordRunnable: Runnable? = null
    /** Locks drag / pinch / rotate and sliders once the user confirms placement. */
    private var isModelTransformLocked: Boolean = false
    /** Custom floor drag: re-anchor to hit-test, not local model offset. */
    private var isPlacementDragging: Boolean = false
    private var dragStartX: Float = 0f
    private var dragStartY: Float = 0f
    private var lastReanchorAtMs: Long = 0L

    /** Contextual AR guidance; hidden once the model is anchored. */
    private var arTipsBanner: TextView? = null
    private var placementReticle: PlacementReticleView? = null
    private var reticleSizePx: Int = 0
    private var lastGuidanceUiAtMs: Long = 0L
    private var darkTipFrameCount: Int = 0
    private var shownTipKey: String? = null
    private var shownTipPriority: Int = Int.MAX_VALUE
    private var candidateTipKey: String? = null
    private var candidateTipMessage: String? = null
    private var candidateTipSinceMs: Long = 0L
    private var planeHideFrameCounter: Int = 0
    private var arSessionReadyAtMs: Long = 0L
    private var depthOcclusionActive: Boolean = false
    private var sessionDepthMode: Config.DepthMode = Config.DepthMode.DISABLED

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Allow drawing behind system bars so [applyWindowInsetsToOverlays] receives
        // real status / nav / gesture insets and can offset the chrome correctly.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        prefs = getSharedPreferences("ar_editor_prefs", MODE_PRIVATE)

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

            // Variant list for the in-editor model gallery (may come from launch cache).
            val variantsJson = when {
                extras.getBoolean("variantProductsFromCache", false) ->
                    ArEditorLaunchCache.takeVariantProductsJson()
                else -> extras.getString("variantProductsJson")
            }
            initialProductId = extras.getString("initialProductId")

            variantProducts = parseVariantsJson(variantsJson)
            applyTappedProductAsActiveModel()

            // Restore placement transforms only — never swap away from the tapped product.
            loadRestoredPlacementState()
        }

        // --------------------------------------------------------------------
        // 2. Build a full‑screen ARSceneView as the background content view.
        // --------------------------------------------------------------------
        //
        // We wrap the SceneView in a simple FrameLayout so it can cleanly fill
        // the window. A compact overlay toolbar is then layered on top to
        // provide scale controls + instructions without obscuring the scene.
        val rootLayout = FrameLayout(this)

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
                // Depth API (e.g. Infinix HOT 60i): AUTOMATIC first, RAW fallback.
                sessionDepthMode = when {
                    session.isDepthModeSupported(Config.DepthMode.AUTOMATIC) ->
                        Config.DepthMode.AUTOMATIC
                    session.isDepthModeSupported(Config.DepthMode.RAW_DEPTH_ONLY) ->
                        Config.DepthMode.RAW_DEPTH_ONLY
                    else -> Config.DepthMode.DISABLED
                }
                config.depthMode = sessionDepthMode
                Log.d(
                    "ArEditorActivity",
                    "AR depth mode: $sessionDepthMode (occlusion after warmup if supported)"
                )

                // Prefer strict plane-anchored placement for better floor contact
                // (reduces the "floating" feel from approximate instant placement).
                config.instantPlacementMode = Config.InstantPlacementMode.DISABLED

                // HDR for sun direction; neutral IBL + disabled live reflections keep
                // wood tones close to the in-app ModelViewer (see applyCatalogMatchedArRendering).
                config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
            }

            onSessionCreated = { _ ->
                arSessionReadyAtMs = SystemClock.uptimeMillis()
                depthOcclusionActive = false
                post {
                    applyCatalogMatchedArRendering()
                    if (modelInstance == null) {
                        preloadModelInstance()
                    }
                }
            }

            onSessionFailed = { error: Exception ->
                Log.e("ArEditorActivity", "AR session failed", error)
                runOnUiThread {
                    Toast.makeText(
                        this@ArEditorActivity,
                        "AR is unavailable on this device",
                        Toast.LENGTH_LONG,
                    ).show()
                    finish()
                }
            }

            // Once per ARCore frame, if we have a loaded model and haven't
            // placed it yet, try to auto-place it on the first tracked
            // horizontal plane under the screen centre. This makes the product
            // appear automatically at 100% size when the scene opens.
            onSessionUpdated = { _: Session, frame: Frame ->
                try {
                    planeHideFrameCounter += 1
                    if (planeHideFrameCounter >= PLANE_HIDE_EVERY_N_FRAMES) {
                        planeHideFrameCounter = 0
                        hidePlaneVisualizationKeepShadows()
                    }
                    updateArGuidanceAndReticle(frame)
                    maybeEnableDepthOcclusion(frame)
                    // Auto-place at screen centre (or restored point) as soon as a floor is found.
                    tryAutoPlaceModel()
                    // Keep overlay labels/persistence in sync with gesture edits.
                    runOnUiThread {
                        try {
                            updateScaleAndSizeLabels()
                            maybePersistUserEdits()
                        } catch (t: Throwable) {
                            Log.e("ArEditorActivity", "overlay sync crash guard", t)
                        }
                    }
                } catch (t: Throwable) {
                    // Prevent hard crashes from non-fatal UI/persistence issues.
                    Log.e("ArEditorActivity", "onSessionUpdated crash guard", t)
                }
            }

            // Drag = re-anchor to floor under finger (not local position offset).
            // Return false so pinch/rotate still reach SceneView when not dragging.
            onTouchEvent = { motionEvent: MotionEvent, _ ->
                handlePlacementDragTouch(motionEvent)
                false
            }
        }

        rootLayout.addView(
            arSceneView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        hidePlaneVisualizationKeepShadows()
        attachPlacementReticle(rootLayout)
        // Build and attach a minimal overlay toolbar that:
        // - Surfaces a readable scale + size status.
        // - Provides explicit +/- buttons as an alternative to pinch gesture.
        // - Gives short AR usage hints that work in both portrait & landscape.
        attachPlacementControlsPanel(rootLayout)

        // Center-top AR usage tips (dismissed once the model is placed).
        attachArTipsBanner(rootLayout)
        // Top-left hint icon to re-open usage instructions on demand.
        attachTipsHintButton(rootLayout)
        // One-button toggle: hide/show BOTH overlays together.
        attachOverlaysEyeToggleButton(rootLayout)

        setContentView(rootLayout)
        // Push overlays inside status / nav / gesture insets so nothing sits under
        // system bars or the landscape nav rail.
        applyWindowInsetsToOverlays(rootLayout)

        // --------------------------------------------------------------------
        // 4. Camera permission check (basic handling).
        // --------------------------------------------------------------------
        //
        // This keeps the Activity from crashing on devices where the camera
        // permission hasn't been granted yet.
        ensureCameraPermission()

        // --------------------------------------------------------------------
        // 5. Kick off background model loading for auto-place.
        // --------------------------------------------------------------------
        //
        // We resolve the GLB referenced by [modelSrc] using SceneView's
        // built‑in [ModelLoader]. Once loaded, taps can reuse this single
        // [ModelInstance] and attach it to new anchors instantly.
        preloadModelInstance()
    }

    /**
     * Match product-detail [ModelViewer] look: neutral studio IBL, not chrome-like live HDR
     * reflections from sky/walls. Also enables depth occlusion when supported.
     */
    private fun applyCatalogMatchedArRendering() {
        try {
            val neutralEnv = arSceneView.environmentLoader.createKTX1Environment(
                "environments/neutral/neutral_ibl.ktx",
                "environments/neutral/neutral_skybox.ktx"
            )
            arSceneView.environment = neutralEnv
            // Neutral IBL only — keep the live camera feed (do not apply studio skybox).
            arSceneView.indirectLight = neutralEnv.indirectLight
        } catch (t: Throwable) {
            Log.w("ArEditorActivity", "Failed to apply neutral IBL environment", t)
        }

        try {
            arSceneView.lightEstimator?.apply {
                // Keep live sun direction + intensity for believable shadows.
                environmentalHdrMainLightDirection = true
                environmentalHdrMainLightIntensity = true
                // Live HDR cubemap from the camera makes wood/marble read as silver outdoors.
                environmentalHdrReflections = false
                environmentalHdrSpecularFilter = false
            }
        } catch (_: Throwable) {
        }

        enableArShadowRendering()
        // Depth occlusion is enabled after warmup in [maybeEnableDepthOcclusion] when supported.
        hidePlaneVisualizationKeepShadows()
    }

    /**
     * SceneView ships with [com.google.android.filament.View.setShadowingEnabled] off.
     * Turn it on and keep invisible planes as shadow receivers so models cast
     * soft shadows onto the detected floor.
     */
    private fun enableArShadowRendering() {
        try {
            arSceneView.view.setShadowingEnabled(true)
        } catch (t: Throwable) {
            Log.w("ArEditorActivity", "view shadowing enable failed", t)
        }

        try {
            arSceneView.mainLightNode?.apply {
                isShadowCaster = true
            }
        } catch (t: Throwable) {
            Log.w("ArEditorActivity", "main light shadow caster failed", t)
        }

        applyPlaneShadowReceiverSettings()
        modelNode?.configureArShadows()
    }

    /**
     * Invisible detected planes still receive model shadows onto the real floor.
     * Must run after [hideArDebugVisualizers] — that helper must not disable the plane renderer.
     */
    private fun applyPlaneShadowReceiverSettings() {
        try {
            val renderer: PlaneRenderer = arSceneView.planeRenderer
            renderer.isEnabled = true
            renderer.isVisible = false
            renderer.isShadowReceiver = true
        } catch (t: Throwable) {
            Log.w("ArEditorActivity", "plane shadow receiver setup failed", t)
        }
    }

    /**
     * Hides ARCore plane dots/point cloud. Keeps plane renderer alive for floor shadows.
     */
    private fun hidePlaneVisualizationKeepShadows() {
        hideArDebugVisualizers()
        applyPlaneShadowReceiverSettings()
    }

    /**
     * Enables Depth API occlusion once tracking is stable (device must support depth in session).
     * Your Infinix HOT 60i lists Depth API — occlusion was previously forced off in code.
     */
    private fun maybeEnableDepthOcclusion(frame: Frame) {
        if (depthOcclusionActive) return
        if (sessionDepthMode == Config.DepthMode.DISABLED) return
        if (frame.camera.trackingState != TrackingState.TRACKING) return
        if (arSessionReadyAtMs <= 0L) return
        if (SystemClock.uptimeMillis() - arSessionReadyAtMs < DEPTH_OCCLUSION_WARMUP_MS) return

        try {
            arSceneView.cameraStream?.isDepthOcclusionEnabled = true
            depthOcclusionActive = true
            Log.d("ArEditorActivity", "Depth occlusion ON (mode=$sessionDepthMode)")
        } catch (t: Throwable) {
            Log.w("ArEditorActivity", "Depth occlusion enable failed", t)
        }
    }

    /**
     * Floor placement: lowest horizontal plane under the ray (reduces "floating" on elevated planes).
     */
    private fun hitTestFloor(xPx: Float, yPx: Float): HitResult? {
        val hits = arSceneView.frame?.hitTest(xPx, yPx) ?: return null
        return hits
            .filter { hit ->
                val trackable = hit.trackable
                trackable is Plane &&
                    trackable.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                    trackable.trackingState == TrackingState.TRACKING
            }
            .minByOrNull { it.hitPose.ty() }
    }

    private fun hideArDebugVisualizers() {
        try {
            listOf("setIsPointCloudVisible", "setPointCloudVisible").forEach { methodName ->
                try {
                    arSceneView.javaClass.methods
                        .firstOrNull { it.name == methodName && it.parameterCount == 1 }
                        ?.invoke(arSceneView, false)
                } catch (_: Throwable) {
                }
            }
            listOf("setIsPlaneRendererVisible", "setPlaneRendererVisible").forEach { methodName ->
                try {
                    arSceneView.javaClass.methods
                        .firstOrNull { it.name == methodName && it.parameterCount == 1 }
                        ?.invoke(arSceneView, false)
                } catch (_: Throwable) {
                }
            }

            fun disableRenderer(obj: Any?) {
                if (obj == null) return
                val clazz = obj.javaClass
                listOf("setEnabled", "setVisible", "setIsEnabled", "setIsVisible").forEach { name ->
                    clazz.methods.firstOrNull { it.name == name && it.parameterCount == 1 }?.let { m ->
                        try {
                            m.invoke(obj, false)
                        } catch (_: Throwable) {
                        }
                    }
                }
                listOf("isEnabled", "enabled", "isVisible", "visible").forEach { fieldName ->
                    try {
                        val f = clazz.declaredFields.firstOrNull { it.name == fieldName }
                        if (f != null) {
                            f.isAccessible = true
                            if (f.type == Boolean::class.javaPrimitiveType || f.type == Boolean::class.java) {
                                f.setBoolean(obj, false)
                            }
                        }
                    } catch (_: Throwable) {
                    }
                }
            }

            fun tryDisableFromGetter(getterName: String) {
                try {
                    val target =
                        arSceneView.javaClass.methods
                            .firstOrNull { it.name == getterName && it.parameterCount == 0 }
                            ?.invoke(arSceneView)
                    disableRenderer(target)
                } catch (_: Throwable) {
                }
            }

            // Do NOT disable planeRenderer — it projects ground shadows for placed models.
            tryDisableFromGetter("getPointCloudRenderer")
            tryDisableFromGetter("getPointCloud")
            tryDisableFromGetter("getPointCloudNode")
            tryDisableFromGetter("getDebugRenderer")
            tryDisableFromGetter("getArCoreDebugRenderer")

        } catch (_: Throwable) {
        }
    }

    /**
     * Placement moves use custom hit-test re-anchoring in [handlePlacementDragTouch],
     * not SceneView's built-in [AnchorNode] drag (which detaches anchors differently).
     */
    private fun configurePlacedAnchorNode(anchor: AnchorNode) {
        anchor.isEditable = false
        anchor.isPositionEditable = false
        anchor.isRotationEditable = false
        anchor.isScaleEditable = false
        anchor.isSmoothTransformEnabled = false
        anchor.updateAnchorPose = true
    }

    /**
     * Finger drag on the floor: repeatedly hit-test and [reanchorModel] (throttled).
     * Ignored while [isModelTransformLocked] or before a model is placed.
     */
    private fun handlePlacementDragTouch(motionEvent: MotionEvent) {
        if (isModelTransformLocked || modelNode == null || anchorNode == null) {
            isPlacementDragging = false
            return
        }
        if (motionEvent.pointerCount > 1) {
            isPlacementDragging = false
            return
        }

        when (motionEvent.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                isPlacementDragging = false
                dragStartX = motionEvent.x
                dragStartY = motionEvent.y
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = kotlin.math.abs(motionEvent.x - dragStartX)
                val dy = kotlin.math.abs(motionEvent.y - dragStartY)
                if (dx > DRAG_THRESHOLD_PX || dy > DRAG_THRESHOLD_PX) {
                    isPlacementDragging = true
                }
                if (isPlacementDragging) {
                    tryReanchorAtScreen(motionEvent.x, motionEvent.y)
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (isPlacementDragging) {
                    tryReanchorAtScreen(motionEvent.x, motionEvent.y, force = true)
                    maybePersistUserEdits(force = true)
                }
                isPlacementDragging = false
            }
        }
    }

    /**
     * Hit-test the floor and move the anchor to that pose. Throttled during MOVE;
     * [force] skips throttle on pointer up for a final snap.
     */
    private fun tryReanchorAtScreen(xPx: Float, yPx: Float, force: Boolean = false): Boolean {
        val currentModel = modelNode ?: return false
        val currentAnchor = anchorNode ?: return false

        val nowMs = SystemClock.elapsedRealtime()
        if (!force && nowMs - lastReanchorAtMs < REANCHOR_MIN_INTERVAL_MS) {
            return false
        }

        val hit = hitTestFloor(xPx, yPx) ?: return false

        lastReanchorAtMs = nowMs
        reanchorModel(hit, currentModel, currentAnchor)

        if (arSceneView.width > 0 && arSceneView.height > 0) {
            lastHitXNorm = xPx / arSceneView.width
            lastHitYNorm = yPx / arSceneView.height
        }
        return true
    }

    private fun applyModelTransformLockState() {
        val node = modelNode ?: return
        val anchor = anchorNode ?: return
        val editable = !isModelTransformLocked

        configurePlacedAnchorNode(anchor)

        // Position moves via [handlePlacementDragTouch]; never local ModelNode offset drag.
        node.isEditable = true
        node.isPositionEditable = false
        node.isRotationEditable = editable
        node.isScaleEditable = editable
        node.isSmoothTransformEnabled = false

        val sliderAlpha = if (editable) 1f else 0.42f
        scaleSeekBar?.isEnabled = editable
        scaleSeekBar?.alpha = sliderAlpha
        rotationSeekBar?.isEnabled = editable
        rotationSeekBar?.alpha = sliderAlpha
    }

    /**
     * Bottom placement panel:
     * - Scale slider + live dimensions
     * - Rotation slider
     * - Place Model + product thumbnail row
     *
     * After Place Model, [captureControlsContainer] replaces this block.
     */
    private fun attachPlacementControlsPanel(root: FrameLayout) {
        fun dpToPx(dp: Int): Int = (dp * resources.displayMetrics.density).roundToInt()

        fun createSliderLabel(text: String): TextView {
            return TextView(this).apply {
                this.text = text
                setTextColor(0xFFE8E8E8.toInt())
                textSize = 12f
                setPadding(0, dpToPx(4), 0, dpToPx(2))
            }
        }

        fun createPillButton(label: String, onClick: () -> Unit): TextView {
            return TextView(this).apply {
                text = label
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(0xFFFFFFFF.toInt())
                setPadding(dpToPx(20), dpToPx(10), dpToPx(20), dpToPx(10))
                background =
                    ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_overlay_control)
                isClickable = true
                isFocusable = true
                setOnClickListener { onClick() }
            }
        }

        fun createProductNameLabel(): TextView {
            return TextView(this).apply {
                text = currentProductName()
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 15f
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, 0, 0, dpToPx(8))
            }
        }

        fun createIconPillButton(iconResId: Int, contentDesc: String, onClick: () -> Unit): FrameLayout {
            val pillHeight = dpToPx(48)
            return FrameLayout(this).apply {
                background =
                    ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_overlay_control)
                val btn = ImageButton(this@ArEditorActivity).apply {
                    setImageResource(iconResId)
                    setBackgroundColor(0x00000000)
                    scaleType = ImageView.ScaleType.CENTER_INSIDE
                    setPadding(dpToPx(12), dpToPx(12), dpToPx(12), dpToPx(12))
                    contentDescription = contentDesc
                    setOnClickListener { onClick() }
                }
                addView(
                    btn,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        pillHeight
                    )
                )
            }
        }

        val panelWidthPx = computeOverlayWidthPx()
        scaleOverlayWidthPx = panelWidthPx

        val rootPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            elevation = 12f
        }
        bottomControlsPanel = rootPanel

        // --- First set: placement controls (scale, rotation, place + thumbnail) ---
        val placementBlock = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(16), dpToPx(12), dpToPx(16), dpToPx(12))
            background = ContextCompat.getDrawable(
                this@ArEditorActivity,
                R.drawable.bg_ar_panel_rounded_border
            )
        }
        placementControlsContainer = placementBlock

        placementProductNameLabel = createProductNameLabel()
        placementBlock.addView(placementProductNameLabel)

        placementBlock.addView(createSliderLabel("Scale"))
        scaleFactorLabel = TextView(this).apply {
            text = "1.00×"
            setTextColor(0xFFBBBBBB.toInt())
            textSize = 11f
            setPadding(0, 0, 0, dpToPx(2))
        }
        placementBlock.addView(scaleFactorLabel)

        val scaleBar = SeekBar(this).apply {
            max = 1000
            progress = scaleToSeekProgress(1f)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (!fromUser || isSyncingSlidersFromModel) return
                    applyUniformScale(seekProgressToScale(progress))
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {
                    maybePersistUserEdits(force = true)
                }
            })
        }
        scaleSeekBar = scaleBar
        placementBlock.addView(
            scaleBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        dimensionsLabel = TextView(this).apply {
            text = "—"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 12f
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dpToPx(4), 0, dpToPx(8))
        }
        placementBlock.addView(dimensionsLabel)

        placementBlock.addView(createSliderLabel("Rotation"))
        val rotationBar = SeekBar(this).apply {
            max = 360
            progress = 0
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (!fromUser || isSyncingSlidersFromModel) return
                    applyYawRotation(progress.toFloat())
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {
                    maybePersistUserEdits(force = true)
                }
            })
        }
        rotationSeekBar = rotationBar
        placementBlock.addView(
            rotationBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        val bottomRow = FrameLayout(this).apply {
            setPadding(0, dpToPx(8), 0, 0)
        }
        val placeBtn = createPillButton("Place Model") { onPlaceModelTapped() }
        placeModelButton = placeBtn
        bottomRow.addView(
            placeBtn,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_HORIZONTAL
            )
        )

        val thumbSize = dpToPx(52)
        val thumbBtn = ImageButton(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background =
                ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_variant_thumb_unselected)
            setPadding(dpToPx(4), dpToPx(4), dpToPx(4), dpToPx(4))
            contentDescription = "Browse 3D models"
            setOnClickListener { showModelGalleryDialog() }
        }
        productThumbnailButton = thumbBtn
        bottomRow.addView(
            thumbBtn,
            FrameLayout.LayoutParams(thumbSize, thumbSize, Gravity.END or Gravity.CENTER_VERTICAL)
        )
        placementBlock.addView(bottomRow)
        rootPanel.addView(placementBlock)

        // --- Second set: capture controls (hidden until Place Model) ---
        val captureBlock = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(dpToPx(16), dpToPx(12), dpToPx(16), dpToPx(12))
            background = ContextCompat.getDrawable(
                this@ArEditorActivity,
                R.drawable.bg_ar_panel_rounded_border
            )
        }
        captureControlsContainer = captureBlock

        captureProductNameLabel = createProductNameLabel()
        captureBlock.addView(captureProductNameLabel)

        val modeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dpToPx(10))
        }
        val photoBtn = TextView(this).apply {
            text = "Photo"
            textSize = 15f
            setTextColor(0xFFFFFFFF.toInt())
            setPadding(dpToPx(24), dpToPx(8), dpToPx(24), dpToPx(8))
            setOnClickListener { selectCaptureKind(CaptureKind.PHOTO) }
        }
        photoModeButton = photoBtn
        val videoBtn = TextView(this).apply {
            text = "Video"
            textSize = 15f
            setTextColor(0x88FFFFFF.toInt())
            setPadding(dpToPx(24), dpToPx(8), dpToPx(24), dpToPx(8))
            setOnClickListener { selectCaptureKind(CaptureKind.VIDEO) }
        }
        videoModeButton = videoBtn
        modeRow.addView(photoBtn)
        modeRow.addView(videoBtn)
        captureBlock.addView(modeRow)

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val captureBtnWrap = createIconPillButton(
            R.drawable.ic_ar_camera,
            "Capture photo"
        ) { onCaptureActionTapped() }
        captureActionButton = captureBtnWrap.getChildAt(0) as ImageButton
        actionRow.addView(
            captureBtnWrap,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginEnd = dpToPx(8)
            }
        )
        val unlockBtnWrap = createIconPillButton(
            R.drawable.ic_arrow_back,
            "Unlock model position"
        ) { onUnlockTapped() }
        unlockButton = unlockBtnWrap.getChildAt(0) as ImageButton
        actionRow.addView(
            unlockBtnWrap,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        )
        captureBlock.addView(actionRow)
        rootPanel.addView(captureBlock)

        selectCaptureKind(CaptureKind.PHOTO)
        updateProductNameLabel()

        val layoutParams = FrameLayout.LayoutParams(
            panelWidthPx,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            marginStart = dpToPx(16)
            marginEnd = dpToPx(16)
            bottomMargin = dpToPx(24)
        }
        root.addView(rootPanel, layoutParams)
        rootPanel.post {
            updateProductThumbnail()
            updateProductNameLabel()
        }
    }

    private fun currentProductName(): String {
        return variantProducts.getOrNull(selectedVariantIndex)?.name
            ?: altText
            ?: "Product"
    }

    private fun updateProductNameLabel() {
        val name = currentProductName()
        placementProductNameLabel?.text = name
        captureProductNameLabel?.text = name
    }

    private fun computeOverlayWidthPx(): Int {
        fun dp(dp: Int): Int = (dp * resources.displayMetrics.density).roundToInt()
        val screenW = resources.displayMetrics.widthPixels
        val isLandscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val marginStart = dp(if (isLandscape) 28 else 16)
        val marginEnd = dp(if (isLandscape) 56 else 16)
        val desired = (screenW * 0.88f).toInt().coerceIn(dp(280), dp(480))
        val maxForPanel = screenW - marginStart - marginEnd
        return desired.coerceAtMost(maxForPanel.coerceAtLeast(dp(240)))
    }

    private fun scaleToSeekProgress(scale: Float): Int {
        val clamped = scale.coerceIn(0.3f, 4.0f)
        return ((clamped - 0.3f) / 3.7f * 1000f).roundToInt().coerceIn(0, 1000)
    }

    private fun seekProgressToScale(progress: Int): Float {
        return (0.3f + (progress.coerceIn(0, 1000) / 1000f) * 3.7f).coerceIn(0.3f, 4.0f)
    }

    private fun applyUniformScale(scale: Float) {
        if (isModelTransformLocked) return
        val node = modelNode ?: return
        val uniform = scale.coerceIn(0.3f, 4.0f)
        val current = node.scale
        val newScale = Scale(uniform, uniform, uniform)
        if (newScale != current) {
            node.scale = newScale
            node.seatOnFloorAnchor()
            updateScaleAndSizeLabels()
            maybePersistUserEdits()
        }
    }

    private fun applyYawRotation(yawDegrees: Float) {
        if (isModelTransformLocked) return
        val node = modelNode ?: return
        val yaw = ((yawDegrees % 360f) + 360f) % 360f
        node.rotation = Rotation(x = 0f, y = yaw, z = 0f)
        maybePersistUserEdits()
    }

    private fun onPlaceModelTapped() {
        if (modelNode == null || anchorNode == null) {
            Toast.makeText(this, "Wait for the model to appear first", Toast.LENGTH_SHORT).show()
            return
        }
        isCaptureMode = true
        isModelTransformLocked = true
        applyModelTransformLockState()
        maybePersistUserEdits(force = true)
        placementControlsContainer?.visibility = View.GONE
        captureControlsContainer?.visibility = View.VISIBLE
        Toast.makeText(this, "Position locked — capture or unlock to move again", Toast.LENGTH_SHORT).show()
    }

    private fun onUnlockTapped() {
        if (isVideoRecording) stopVideoRecording()
        isCaptureMode = false
        isModelTransformLocked = false
        applyModelTransformLockState()
        captureControlsContainer?.visibility = View.GONE
        placementControlsContainer?.visibility = View.VISIBLE
        Toast.makeText(this, "You can move the model again", Toast.LENGTH_SHORT).show()
    }

    private fun selectCaptureKind(kind: CaptureKind) {
        captureKind = kind
        val selected = 0xFFFFFFFF.toInt()
        val muted = 0x88FFFFFF.toInt()
        photoModeButton?.setTextColor(if (kind == CaptureKind.PHOTO) selected else muted)
        videoModeButton?.setTextColor(if (kind == CaptureKind.VIDEO) selected else muted)
        updateCaptureActionButtonUi()
    }

    private fun updateCaptureActionButtonUi() {
        val btn = captureActionButton ?: return
        btn.setImageResource(R.drawable.ic_ar_camera)
        btn.contentDescription = when {
            captureKind == CaptureKind.VIDEO && isVideoRecording -> "Stop recording"
            captureKind == CaptureKind.VIDEO -> "Start recording"
            else -> "Capture photo"
        }
        btn.alpha = if (captureKind == CaptureKind.VIDEO && isVideoRecording) 0.72f else 1f
    }

    private fun onCaptureActionTapped() {
        when (captureKind) {
            CaptureKind.PHOTO -> captureArScreenshot()
            CaptureKind.VIDEO -> {
                if (isVideoRecording) stopVideoRecording() else startVideoRecording()
            }
        }
    }

    private fun updateProductThumbnail() {
        val btn = productThumbnailButton ?: return
        val variant = variantProducts.getOrNull(selectedVariantIndex)
        val url = variant?.thumbnailUrl
        if (!url.isNullOrBlank()) {
            btn.load(url) {
                crossfade(true)
                transformations(CircleCropTransformation())
                placeholder(R.drawable.bg_variant_placeholder)
                error(R.drawable.bg_variant_placeholder)
            }
        } else {
            btn.setImageResource(R.drawable.bg_variant_placeholder)
        }
        btn.contentDescription = variant?.name ?: altText ?: "Browse 3D models"
        updateProductNameLabel()
    }

    private fun showModelGalleryDialog() {
        if (variantProducts.isEmpty()) {
            Toast.makeText(this, "No other models available", Toast.LENGTH_SHORT).show()
            return
        }

        fun dpToPx(dp: Int): Int = (dp * resources.displayMetrics.density).roundToInt()
        val dialogView = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(16), dpToPx(12), dpToPx(16), dpToPx(8))
        }

        val filterRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dpToPx(8))
        }

        val searchField = EditText(this).apply {
            hint = "Search models"
            setSingleLine(true)
            setTextColor(0xFF111111.toInt())
            setHintTextColor(0xFF888888.toInt())
            setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10))
        }
        filterRow.addView(
            searchField,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginEnd = dpToPx(8)
            }
        )

        val categories = listOf("All") + variantProducts
            .map { it.category.trim().ifEmpty { "Other" } }
            .distinct()
            .sorted()
        var selectedCategory = "All"
        val categorySpinner = Spinner(this).apply {
            adapter = ArrayAdapter(
                this@ArEditorActivity,
                android.R.layout.simple_spinner_dropdown_item,
                categories
            )
            setSelection(0)
        }
        filterRow.addView(
            categorySpinner,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )
        dialogView.addView(filterRow)

        val scroll = android.widget.ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(320)
            )
        }
        val gridHost = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        scroll.addView(gridHost)
        dialogView.addView(scroll)

        val dialog = AlertDialog.Builder(this)
            .setTitle("3D Models")
            .setView(dialogView)
            .setNegativeButton("Close", null)
            .create()

        fun rebuildGrid(query: String, categoryFilter: String) {
            gridHost.removeAllViews()
            val q = query.trim().lowercase()
            val filtered = variantProducts.filter { variant ->
                val category = variant.category.trim().ifEmpty { "Other" }
                val categoryOk = categoryFilter == "All" || category == categoryFilter
                val searchOk = q.isEmpty() || variant.name.lowercase().contains(q)
                categoryOk && searchOk
            }
            if (filtered.isEmpty()) {
                gridHost.addView(
                    TextView(this@ArEditorActivity).apply {
                        text = "No models match your search"
                        setTextColor(0xFF666666.toInt())
                        setPadding(0, dpToPx(16), 0, dpToPx(16))
                    }
                )
                return
            }

            val columns = 3
            var row: LinearLayout? = null
            filtered.forEachIndexed { index, variant ->
                if (index % columns == 0) {
                    row = LinearLayout(this@ArEditorActivity).apply {
                        orientation = LinearLayout.HORIZONTAL
                        setPadding(0, dpToPx(6), 0, dpToPx(6))
                    }
                    gridHost.addView(row)
                }
                val cell = LinearLayout(this@ArEditorActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER_HORIZONTAL
                    setPadding(dpToPx(4), dpToPx(4), dpToPx(4), dpToPx(4))
                    val globalIndex = variantProducts.indexOfFirst { it.productId == variant.productId }
                    setOnClickListener {
                        if (globalIndex >= 0) {
                            swapVariantModel(globalIndex)
                            updateProductThumbnail()
                        }
                        dialog.dismiss()
                    }
                }
                val thumb = ImageView(this@ArEditorActivity).apply {
                    layoutParams = LinearLayout.LayoutParams(dpToPx(72), dpToPx(72))
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    val url = variant.thumbnailUrl
                    if (!url.isNullOrBlank()) {
                        load(url) {
                            crossfade(true)
                            transformations(CircleCropTransformation())
                            placeholder(R.drawable.bg_variant_placeholder)
                            error(R.drawable.bg_variant_placeholder)
                        }
                    } else {
                        setImageResource(R.drawable.bg_variant_placeholder)
                    }
                }
                val name = TextView(this@ArEditorActivity).apply {
                    text = variant.name
                    textSize = 10f
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    gravity = Gravity.CENTER_HORIZONTAL
                    setTextColor(0xFF222222.toInt())
                }
                cell.addView(thumb)
                cell.addView(name)
                row?.addView(
                    cell,
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                )
            }
        }

        searchField.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                rebuildGrid(s?.toString().orEmpty(), selectedCategory)
            }
            override fun afterTextChanged(s: android.text.Editable?) {}
        })

        categorySpinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onItemSelected(
                parent: android.widget.AdapterView<*>?,
                view: View?,
                position: Int,
                id: Long
            ) {
                selectedCategory = categories.getOrNull(position) ?: "All"
                rebuildGrid(searchField.text?.toString().orEmpty(), selectedCategory)
            }
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
        }

        rebuildGrid("", "All")
        dialog.show()
    }

    private fun startVideoRecording() {
        if (isVideoRecording) return
        isVideoRecording = true
        videoFrameBitmaps.clear()
        updateCaptureActionButtonUi()
        Toast.makeText(this, "Recording…", Toast.LENGTH_SHORT).show()
        videoRecordHandler = Handler(Looper.getMainLooper())
        videoRecordRunnable = object : Runnable {
            override fun run() {
                if (!isVideoRecording) return
                captureArFrameBitmap { bitmap ->
                    if (bitmap != null) videoFrameBitmaps.add(bitmap)
                }
                videoRecordHandler?.postDelayed(this, 125L)
            }
        }
        videoRecordHandler?.post(videoRecordRunnable!!)
    }

    private fun stopVideoRecording() {
        if (!isVideoRecording) return
        isVideoRecording = false
        videoRecordRunnable?.let { videoRecordHandler?.removeCallbacks(it) }
        videoRecordRunnable = null
        updateCaptureActionButtonUi()
        val frames = videoFrameBitmaps.toList()
        videoFrameBitmaps.clear()
        if (frames.isEmpty()) {
            Toast.makeText(this, "No frames captured", Toast.LENGTH_SHORT).show()
            return
        }
        Thread {
            val uri = ArMp4Recorder.saveFramesAsMp4(this, frames, fps = 8)
            frames.forEach { it.recycle() }
            runOnUiThread {
                if (uri != null) {
                    Toast.makeText(this, "Video saved to gallery", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, "Video save failed", Toast.LENGTH_SHORT).show()
                }
            }
        }.start()
    }

    private fun captureArFrameBitmap(onResult: (Bitmap?) -> Unit) {
        val sourceView = arSceneView
        val w = sourceView.width
        val h = sourceView.height
        if (w <= 0 || h <= 0) {
            onResult(null)
            return
        }
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            PixelCopy.request(sourceView, bitmap, { result ->
                onResult(if (result == PixelCopy.SUCCESS) bitmap else null)
            }, Handler(Looper.getMainLooper()))
        } else {
            val canvas = Canvas(bitmap)
            sourceView.draw(canvas)
            onResult(bitmap)
        }
    }

    /**
     * Applies status / nav / cutout / gesture insets so overlays and the eye
     * control sit in the safe area (fixes overlap with 3-button nav and gestures).
     */
    private fun applyWindowInsetsToOverlays(root: FrameLayout) {
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            val cut = insets.getInsets(WindowInsetsCompat.Type.displayCutout())
            val gest = insets.getInsets(WindowInsetsCompat.Type.systemGestures())
            val d = resources.displayMetrics.density
            fun dp(v: Int) = (v * d).roundToInt()

            val insetTop = maxOf(bars.top, cut.top) + dp(12)
            val insetBottom = maxOf(bars.bottom, gest.bottom) + dp(16)
            val insetStart = maxOf(bars.left, cut.left, gest.left) + dp(8)
            val insetEnd = maxOf(bars.right, cut.right, gest.right) + dp(8)

            val isLandscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val navRailExtra = if (isLandscape) dp(40) else 0

            bottomControlsPanel?.let { v ->
                (v.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                    lp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                    val screenW = resources.displayMetrics.widthPixels
                    lp.bottomMargin = insetBottom + dp(16)
                    lp.marginStart = insetStart + dp(16)
                    lp.marginEnd = insetEnd + dp(16)
                    val availableW = (screenW - lp.marginStart - lp.marginEnd).coerceAtLeast(dp(200))
                    lp.width = scaleOverlayWidthPx.coerceAtMost(availableW)
                    v.layoutParams = lp
                }
            }
            overlaysEyeButton?.let { v ->
                (v.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                    lp.topMargin = insetTop + dp(8)
                    lp.marginEnd = insetEnd + navRailExtra + dp(16)
                    v.layoutParams = lp
                }
            }
            tipsHintButton?.let { v ->
                (v.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                    lp.topMargin = insetTop + dp(8)
                    lp.marginStart = insetStart + dp(16)
                    v.layoutParams = lp
                }
            }
            arTipsBanner?.let { v ->
                (v.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                    lp.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                    val screenH = resources.displayMetrics.heightPixels
                    // Tips sit ~20% down from the top of the screen (plus status bar inset).
                    lp.topMargin = insetTop + (screenH * 0.20f).toInt() + dp(8)
                    lp.marginStart = insetStart + dp(20)
                    lp.marginEnd = insetEnd + dp(20)
                    v.layoutParams = lp
                }
            }
            insets
        }
        ViewCompat.requestApplyInsets(root)
    }

    private fun attachPlacementReticle(root: FrameLayout) {
        fun dpToPx(dp: Int): Int =
            (dp * resources.displayMetrics.density).roundToInt()

        reticleSizePx = dpToPx(72)
        val reticle = PlacementReticleView(this)
        placementReticle = reticle
        root.addView(
            reticle,
            FrameLayout.LayoutParams(
                reticleSizePx,
                reticleSizePx,
                Gravity.TOP or Gravity.START,
            ),
        )
        reticle.visibility = View.INVISIBLE
    }

    private fun positionReticleAt(screenX: Float, screenY: Float) {
        val reticle = placementReticle ?: return
        val half = reticleSizePx / 2f
        reticle.translationX = screenX - half
        reticle.translationY = screenY - half
    }

    /** ARCore world XYZ → screen pixels within [arSceneView]. */
    private fun projectWorldToScreen(frame: Frame, world: FloatArray): Pair<Float, Float>? {
        if (arSceneView.width <= 0 || arSceneView.height <= 0) return null

        val viewMatrix = FloatArray(16)
        val projMatrix = FloatArray(16)
        frame.camera.getViewMatrix(viewMatrix, 0)
        frame.camera.getProjectionMatrix(projMatrix, 0, 0.1f, 100f)

        val worldHomogeneous = floatArrayOf(world[0], world[1], world[2], 1f)
        val viewHomogeneous = FloatArray(4)
        val clipHomogeneous = FloatArray(4)
        Matrix.multiplyMV(viewHomogeneous, 0, viewMatrix, 0, worldHomogeneous, 0)
        Matrix.multiplyMV(clipHomogeneous, 0, projMatrix, 0, viewHomogeneous, 0)

        val w = clipHomogeneous[3]
        if (w <= 0f) return null

        val ndcX = clipHomogeneous[0] / w
        val ndcY = clipHomogeneous[1] / w
        val sx = ((ndcX + 1f) * 0.5f) * arSceneView.width + arSceneView.left
        val sy = ((1f - ndcY) * 0.5f) * arSceneView.height + arSceneView.top
        return Pair(sx, sy)
    }

    private fun modelFootWorldPosition(): FloatArray? {
        val anchor = anchorNode ?: return null
        val node = modelNode ?: return floatArrayOf(
            anchor.worldPosition.x,
            anchor.worldPosition.y,
            anchor.worldPosition.z,
        )
        val anchorPos = anchor.worldPosition
        val local = node.position
        return floatArrayOf(
            anchorPos.x + local.x,
            anchorPos.y + local.y,
            anchorPos.z + local.z,
        )
    }

    private fun centerFloorHitWorldPosition(): FloatArray? {
        if (arSceneView.width <= 0 || arSceneView.height <= 0) return null
        val hit = hitTestFloor(
            arSceneView.width / 2f,
            arSceneView.height / 2f,
        ) ?: return null
        val t = hit.hitPose.translation
        return floatArrayOf(t[0], t[1], t[2])
    }

    private fun reticleTargetWorldPosition(placed: Boolean): FloatArray? {
        return if (placed) modelFootWorldPosition() else centerFloorHitWorldPosition()
    }

    /**
     * Center-top banner driven by [updateArGuidanceAndReticle] (tracking, light,
     * floor hit-test). Removed when [placeAnchoredModel] runs.
     */
    private fun attachArTipsBanner(root: FrameLayout) {
        fun dpToPx(dp: Int): Int =
            (dp * resources.displayMetrics.density).roundToInt()

        val screenW = resources.displayMetrics.widthPixels
        val maxTextW = (screenW * 0.72f).toInt()

        val tv = TextView(this).apply {
            text = "Starting AR…"
            setTextColor(0xFFF5F5F5.toInt())
            textSize = 16f
            setLineSpacing(dpToPx(2).toFloat(), 1f)
            setPadding(dpToPx(16), dpToPx(10), dpToPx(16), dpToPx(10))
            gravity = Gravity.CENTER_HORIZONTAL
            this.maxWidth = maxTextW
            background = ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_tips_subtle)
        }
        arTipsBanner = tv

        val lp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dpToPx(8)
            marginStart = dpToPx(16)
            marginEnd = dpToPx(16)
        }
        root.addView(tv, lp)
    }

    private data class ContextualArTip(
        val priority: Int,
        val key: String,
        val message: String,
    )

    private fun resolveContextualArTip(frame: Frame, centerFloorHit: Boolean): ContextualArTip {
        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) {
            val message = when (camera.trackingFailureReason) {
                TrackingFailureReason.INSUFFICIENT_LIGHT ->
                    "Too dark — add more light"
                TrackingFailureReason.EXCESSIVE_MOTION ->
                    "Move your phone more slowly"
                TrackingFailureReason.INSUFFICIENT_FEATURES ->
                    "Point at a textured surface"
                TrackingFailureReason.BAD_STATE ->
                    "Finding surfaces…"
                else -> "Finding surfaces…"
            }
            return ContextualArTip(
                priority = 0,
                key = "tracking_${camera.trackingFailureReason}",
                message = message,
            )
        }

        val light = frame.lightEstimate
        if (light != null && light.state == LightEstimate.State.VALID) {
            if (light.pixelIntensity < DARK_PIXEL_INTENSITY_THRESHOLD) {
                darkTipFrameCount += 1
            } else {
                darkTipFrameCount = 0
            }
            if (darkTipFrameCount >= DARK_FRAMES_BEFORE_TIP) {
                return ContextualArTip(
                    priority = 1,
                    key = "too_dark",
                    message = "Too dark — add more light",
                )
            }
        } else {
            darkTipFrameCount = 0
        }

        if (modelInstance == null) {
            return ContextualArTip(
                priority = 2,
                key = "loading_model",
                message = "Loading model…",
            )
        }

        if (!centerFloorHit) {
            return ContextualArTip(
                priority = 3,
                key = "no_floor",
                message = "Aim at the floor and move slowly",
            )
        }

        return ContextualArTip(
            priority = 4,
            key = "floor_ready",
            message = "Floor detected — hold steady",
        )
    }

    private fun screenCenterFloorHit(): Boolean {
        if (arSceneView.width <= 0 || arSceneView.height <= 0) return false
        return hitTestFloor(
            arSceneView.width / 2f,
            arSceneView.height / 2f,
        ) != null
    }

    private fun updateArGuidanceAndReticle(frame: Frame) {
        val now = SystemClock.uptimeMillis()
        if (now - lastGuidanceUiAtMs < GUIDANCE_UI_INTERVAL_MS) return
        lastGuidanceUiAtMs = now

        val placed = anchorNode != null && modelNode != null
        val centerHit = if (!placed) screenCenterFloorHit() else false
        val tip = if (!placed) resolveContextualArTip(frame, centerHit) else null
        val footWorld = reticleTargetWorldPosition(placed)
        val footScreen = footWorld?.let { projectWorldToScreen(frame, it) }

        runOnUiThread {
            val reticle = placementReticle
            if (reticle != null && footScreen != null) {
                reticle.visibility = View.VISIBLE
                positionReticleAt(footScreen.first, footScreen.second)
                reticle.isFloorReady = true
            } else {
                reticle?.visibility = View.INVISIBLE
            }

            if (placed) return@runOnUiThread

            val banner = arTipsBanner ?: return@runOnUiThread
            if (tip != null) {
                applyStableContextualTip(banner, tip, now)
            }
        }
    }

    private fun applyStableContextualTip(banner: TextView, tip: ContextualArTip, now: Long) {
        if (tip.priority < shownTipPriority) {
            shownTipPriority = tip.priority
            shownTipKey = tip.key
            candidateTipKey = null
            banner.text = tip.message
            return
        }

        if (tip.key == shownTipKey) {
            if (banner.text != tip.message) banner.text = tip.message
            return
        }

        if (tip.key != candidateTipKey) {
            candidateTipKey = tip.key
            candidateTipMessage = tip.message
            candidateTipSinceMs = now
            return
        }

        if (now - candidateTipSinceMs >= TIP_STABLE_MS) {
            shownTipKey = tip.key
            shownTipPriority = tip.priority
            candidateTipKey = null
            banner.text = tip.message
        }
    }

    private fun attachTipsHintButton(root: FrameLayout) {
        fun dpToPx(dp: Int): Int = (dp * resources.displayMetrics.density).roundToInt()
        val button = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_info_details)
            setBackgroundColor(0x00000000)
            setPadding(dpToPx(10), dpToPx(10), dpToPx(10), dpToPx(10))
            contentDescription = "AR usage instructions"
            setOnClickListener { showArUsageDialog() }
        }
        tipsHintButton = button
        val lp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            marginStart = dpToPx(16)
            topMargin = dpToPx(16)
        }
        root.addView(button, lp)
    }

    private fun showArUsageDialog() {
        AlertDialog.Builder(this)
            .setTitle("How to use AR")
            .setMessage(
                "1) Point at the floor — the model appears automatically.\n\n" +
                    "2) Use the sliders to scale and rotate, or drag to reposition.\n\n" +
                    "3) Tap Place Model when ready, then capture a photo or video.\n\n" +
                    "4) Tap Unlock to move the model again."
            )
            .setPositiveButton("Got it", null)
            .show()
    }

    private fun dismissArTipsBanner() {
        arTipsBanner?.visibility = View.GONE
        arTipsBanner = null
        shownTipKey = null
        shownTipPriority = Int.MAX_VALUE
        candidateTipKey = null
        darkTipFrameCount = 0
    }

    private fun attachOverlaysEyeToggleButton(root: FrameLayout) {
        val dpToPx = { dp: Int -> (dp * resources.displayMetrics.density).roundToInt() }
        val toggleButton = ImageButton(this).apply {
            setImageDrawable(ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.ic_visibility))
            // Transparent eye button per latest UI request (no border).
            setBackgroundColor(0x00000000)
            setPadding(dpToPx(12), dpToPx(12), dpToPx(12), dpToPx(12))
            contentDescription = "Toggle overlay visibility"
            setOnClickListener {
                overlaysVisible = !overlaysVisible
                val visibility = if (overlaysVisible) View.VISIBLE else View.GONE
                bottomControlsPanel?.visibility = visibility

                // Swap icon: eye when visible, eye-off when hidden.
                setImageDrawable(
                    ContextCompat.getDrawable(
                        this@ArEditorActivity,
                        if (overlaysVisible) R.drawable.ic_visibility else R.drawable.ic_visibility_off
                    )
                )
            }
        }

        overlaysEyeButton = toggleButton

        val layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            marginEnd = dpToPx(16)
            topMargin = dpToPx(16)
        }

        root.addView(toggleButton, layoutParams)
    }

    private fun captureArScreenshot() {
        // Capture ONLY the AR camera surface (no overlay UI, no status bar text).
        val sourceView = arSceneView
        val w = sourceView.width
        val h = sourceView.height
        if (w <= 0 || h <= 0) {
            Toast.makeText(this, "Capture failed", Toast.LENGTH_SHORT).show()
            return
        }

        // PixelCopy reads from the actual window pixels, so we must hide the
        // overlay chrome (eye button + panels) before requesting the copy.
        val restoreVis: MutableList<Pair<View, Int>> = mutableListOf()
        fun hide(v: View?) {
            if (v == null) return
            restoreVis += v to v.visibility
            v.visibility = View.GONE
        }

        hide(bottomControlsPanel)
        hide(overlaysEyeButton)
        hide(arTipsBanner)
        hide(placementReticle)
        hide(tipsHintButton)

        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val handler = Handler(Looper.getMainLooper())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            PixelCopy.request(
                sourceView,
                bitmap,
                { result ->
                    if (result == PixelCopy.SUCCESS) {
                        saveScreenshotToGallery(bitmap)
                    } else {
                        Toast.makeText(this, "Capture failed", Toast.LENGTH_SHORT).show()
                    }
                    // Restore UI chrome regardless of success.
                    restoreVis.forEach { (v, vis) -> v.visibility = vis }
                },
                handler
            )
        } else {
            val canvas = Canvas(bitmap)
            sourceView.draw(canvas)
            restoreVis.forEach { (v, vis) -> v.visibility = vis }
            saveScreenshotToGallery(bitmap)
        }
    }

    private fun saveScreenshotToGallery(bitmap: Bitmap) {
        val filename = "smartspace_ar_${System.currentTimeMillis()}.png"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, filename)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/SmartSpace")
            }
        }

        val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        if (uri == null) {
            Toast.makeText(this, "Save failed", Toast.LENGTH_SHORT).show()
            return
        }
        contentResolver.openOutputStream(uri).use { out ->
            if (out == null || !bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                Toast.makeText(this, "Save failed", Toast.LENGTH_SHORT).show()
                return
            }
        }
        Toast.makeText(this, "Captured to gallery", Toast.LENGTH_SHORT).show()
    }

    /**
     * Pops back to Flutter and opens [ProductDetailScreen] for whichever variant
     * is currently active in the carousel.
     */
    private fun openCurrentProductDetailInApp() {
        val fromVariant = variantProducts.getOrNull(selectedVariantIndex)?.productId?.trim()
        val productId = when {
            !fromVariant.isNullOrEmpty() -> fromVariant
            else -> initialProductId?.trim()
        }
        if (productId.isNullOrEmpty()) {
            Toast.makeText(this, "No product linked to this model", Toast.LENGTH_SHORT).show()
            return
        }

        val engine = FlutterEngineCache.getInstance().get(MainActivity.MAIN_ENGINE_ID)
        if (engine == null) {
            Toast.makeText(this, "Unable to open product page", Toast.LENGTH_SHORT).show()
            return
        }

        try {
            MethodChannel(engine.dartExecutor.binaryMessenger, "com.smartspace/ar_editor")
                .invokeMethod("openProductDetail", mapOf("productId" to productId))
            // Close AR so Flutter's pushed route is immediately visible.
            finish()
        } catch (t: Throwable) {
            Log.e("ArEditorActivity", "openProductDetail failed", t)
            Toast.makeText(this, "Unable to open product page", Toast.LENGTH_SHORT).show()
        }
    }

    private fun parseVariantsJson(variantsJson: String?): List<VariantProduct> {
        if (variantsJson == null || variantsJson.isBlank()) return emptyList()
        return try {
            val array = JSONArray(variantsJson)
            val list = mutableListOf<VariantProduct>()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val productId = obj.optString("productId", "unknown_$i")
                val name = obj.optString("name", productId)
                val src = obj.optString("modelSrc", "")

                if (src.isBlank()) continue

                fun optNullableDouble(key: String): Double? {
                    return if (obj.has(key) && !obj.isNull(key)) obj.getDouble(key) else null
                }

                val thumb = obj.optString("thumbnailUrl", "").trim().takeIf { it.isNotEmpty() }

                val category = obj.optString("category", "").trim().ifEmpty { "Other" }
                list.add(
                    VariantProduct(
                        productId = productId,
                        name = name,
                        category = category,
                        modelSrc = src,
                        thumbnailUrl = thumb,
                        realWidthMeters = optNullableDouble("realWidthMeters"),
                        realHeightMeters = optNullableDouble("realHeightMeters"),
                        realDepthMeters = optNullableDouble("realDepthMeters"),
                        modelBaseScale = obj.optDouble("modelBaseScale", 1.0)
                    )
                )
            }
            if (list.isEmpty()) emptyList() else list
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun detachAndDestroyModelNode(anchor: AnchorNode, oldNode: YawLimitedModelNode?) {
        if (oldNode == null) return
        modelNode = null
        try {
            anchor.removeChildNode(oldNode)
        } catch (t: Throwable) {
            Log.w("ArEditorActivity", "removeChildNode during swap", t)
        }
        try {
            oldNode.destroy()
        } catch (t: Throwable) {
            Log.w("ArEditorActivity", "destroy model node during swap", t)
        }
    }

    private fun finishVariantSwapLoad() {
        variantLoadInProgress = false
        val pending = pendingVariantIndex
        pendingVariantIndex = null
        if (pending != null && pending != selectedVariantIndex) {
            swapVariantModel(pending)
        }
    }

    /**
     * Option A: swaps the currently shown model to a different variant.
     *
     * Loads are serialized so two 50MB+ GLBs are never parsed at once (OOM).
     */
    private fun swapVariantModel(variantIndex: Int) {
        val currentVariant = variantProducts.getOrNull(variantIndex) ?: return

        if (variantLoadInProgress) {
            pendingVariantIndex = variantIndex
            selectedVariantIndex = variantIndex
            updateProductThumbnail()
            updateProductNameLabel()
            return
        }

        selectedVariantIndex = variantIndex
        variantLoadInProgress = true

        // Bump request id so late async loads don't apply out of order.
        variantSwapRequestId += 1
        val requestIdSnapshot = variantSwapRequestId

        val preservedScale: Scale? = modelNode?.scale
        val preservedYaw: Float? = modelNode?.rotation?.y
        val preservedPosition: Position? = modelNode?.position

        applyVariantFields(currentVariant)
        updateProductThumbnail()
        updateProductNameLabel()

        loadModelInstanceFromSource(currentVariant.modelSrc) { instance ->
            if (requestIdSnapshot != variantSwapRequestId) {
                finishVariantSwapLoad()
                return@loadModelInstanceFromSource
            }
            if (instance == null) {
                runOnUiThread {
                    Toast.makeText(
                        this@ArEditorActivity,
                        "Could not load ${currentVariant.name}",
                        Toast.LENGTH_SHORT
                    ).show()
                }
                finishVariantSwapLoad()
                return@loadModelInstanceFromSource
            }

            try {
                if (anchorNode == null || modelNode == null) {
                    modelInstance = instance
                    tryAutoPlaceModel()
                    finishVariantSwapLoad()
                    return@loadModelInstanceFromSource
                }

                val anchor = anchorNode
                if (anchor == null) {
                    modelInstance = instance
                    finishVariantSwapLoad()
                    return@loadModelInstanceFromSource
                }

                val oldNode = modelNode
                detachAndDestroyModelNode(anchor, oldNode)

                val newNode = buildSwappedModelNode(
                    instance = instance,
                    preservedScale = preservedScale,
                    preservedYaw = preservedYaw,
                    preservedPosition = preservedPosition,
                )

                // Defer attach one frame so Filament can release the old instance.
                Handler(Looper.getMainLooper()).post {
                    if (requestIdSnapshot != variantSwapRequestId) {
                        try {
                            newNode.destroy()
                        } catch (_: Throwable) {
                        }
                        finishVariantSwapLoad()
                        return@post
                    }
                    try {
                        anchor.addChildNode(newNode)
                        modelNode = newNode
                        modelInstance = instance
                        applyModelTransformLockState()
                        updateScaleAndSizeLabels()
                        maybePersistUserEdits()
                    } catch (t: Throwable) {
                        Log.e("ArEditorActivity", "swapVariantModel attach failed", t)
                        try {
                            newNode.destroy()
                        } catch (_: Throwable) {
                        }
                    } finally {
                        finishVariantSwapLoad()
                    }
                }
            } catch (t: Throwable) {
                Log.e("ArEditorActivity", "swapVariantModel apply failed", t)
                finishVariantSwapLoad()
            }
        }
    }

    private fun buildSwappedModelNode(
        instance: ModelInstance,
        preservedScale: Scale?,
        preservedYaw: Float?,
        preservedPosition: Position?,
    ): YawLimitedModelNode {
        return YawLimitedModelNode(modelInstance = instance).apply {
            isEditable = true
            isPositionEditable = false
            isRotationEditable = true
            isScaleEditable = true
            editableScaleRange = 0.3f..4.0f
            val current = preservedScale
            if (current != null) {
                scale = Scale(
                    x = current.x.coerceIn(0.3f, 4.0f),
                    y = current.y.coerceIn(0.3f, 4.0f),
                    z = current.z.coerceIn(0.3f, 4.0f),
                )
            } else {
                val base = safeBaseScale(modelBaseScale)
                scale = Scale(base, base, base)
            }

            if (preservedYaw != null) {
                rotation = Rotation(x = 0f, y = preservedYaw, z = 0f)
            }
            if (preservedPosition != null) {
                position = Position(preservedPosition.x, 0f, preservedPosition.z)
            }

            configureArShadows()
            seatOnFloorAnchor()
        }
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
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            // For now we simply ignore the result. Once a real AR surface is
            // integrated this is where you would either start the AR session
            // or show a helpful error UI.
        }
    }

    override fun onPause() {
        // Force-save latest transform before backgrounding the activity.
        maybePersistUserEdits(force = true)
        super.onPause()
    }

    override fun onStop() {
        // Extra safety net if lifecycle jumps straight to stopped.
        maybePersistUserEdits(force = true)
        super.onStop()
    }

    // ------------------------------------------------------------------------
    // 5. Model loading + tap‑to‑place helpers
    // ------------------------------------------------------------------------
    //
    // These helpers sit on top of ARSceneView's core ARCore integration. They:
    // - Asynchronously load a single [ModelInstance] from [modelSrc].
    // - On each tap, hit‑test the AR frame against horizontal planes.
    // - If we get a valid hit, create an anchored node and attach a
    //   gesture‑editable [ModelNode] so users can scale and rotate.

    /** True when Filament parsed a GLB that actually contains drawable meshes. */
    private fun modelHasRenderables(instance: ModelInstance): Boolean {
        return try {
            instance.renderableEntities.isNotEmpty()
        } catch (t: Throwable) {
            Log.w("ArEditorActivity", "renderableEntities check failed", t)
            false
        }
    }

    /**
     * Loads a GLB from http(s), file://, or Flutter bundled assets (assets/...).
     */
    private fun loadModelInstanceFromSource(
        rawSource: String,
        onLoaded: (ModelInstance?) -> Unit,
    ) {
        ArModelSourceResolver.resolveAsync(this, rawSource) { resolved ->
            if (resolved == null) {
                Log.e("ArEditorActivity", "Could not resolve model source: $rawSource")
                runOnUiThread {
                    Toast.makeText(
                        this,
                        "3D model file not found",
                        Toast.LENGTH_SHORT
                    ).show()
                }
                onLoaded(null)
                return@resolveAsync
            }

            Log.d("ArEditorActivity", "Loading GLB from: $resolved")
            try {
                arSceneView.modelLoader.loadModelInstanceAsync(resolved) { instance: ModelInstance? ->
                    runOnUiThread {
                        try {
                            if (instance == null) {
                                Log.e("ArEditorActivity", "Filament returned null for: $resolved")
                                Toast.makeText(
                                    this,
                                    "3D model failed to load",
                                    Toast.LENGTH_SHORT
                                ).show()
                                onLoaded(null)
                                return@runOnUiThread
                            }
                            if (!modelHasRenderables(instance)) {
                                Log.e(
                                    "ArEditorActivity",
                                    "GLB has no renderables (check WebP textures?): $resolved"
                                )
                                Toast.makeText(
                                    this,
                                    "3D model has no visible geometry",
                                    Toast.LENGTH_SHORT
                                ).show()
                                onLoaded(null)
                                return@runOnUiThread
                            }
                            Log.d(
                                "ArEditorActivity",
                                "Loaded ${instance.renderableEntities.size} renderables from $resolved"
                            )
                            onLoaded(instance)
                        } catch (t: Throwable) {
                            Log.e("ArEditorActivity", "Model load callback failed", t)
                            onLoaded(null)
                        }
                    }
                }
            } catch (t: Throwable) {
                Log.e("ArEditorActivity", "loadModelInstanceAsync failed for $resolved", t)
                runOnUiThread {
                    Toast.makeText(this, "3D model failed to load", Toast.LENGTH_SHORT).show()
                }
                onLoaded(null)
            }
        }
    }

    /**
     * Starts an asynchronous load of the GLB pointed to by [modelSrc].
     *
     * The load runs on SceneView's internal coroutine scope. Once complete we
     * cache the [ModelInstance] for reuse on future placements.
     */
    private fun preloadModelInstance() {
        val source = modelSrc ?: return
        loadModelInstanceFromSource(source) { instance ->
            modelInstance = instance
        }
    }

    /**
     * Attempts to place the model automatically at the screen centre on the
     * first tracked horizontal plane we can hit-test against.
     *
     * This is invoked every frame via [ARSceneView.onSessionUpdated] but will
     * only succeed once – after placement we keep the existing anchor/model.
     */
    private fun tryAutoPlaceModel() {
        // If we already have an anchor/model in the scene, there's nothing to
        // do. This ensures we only auto-place once.
        if (anchorNode != null || modelNode != null) return

        // Bail out early if we don't yet have a model to show.
        val instance = modelInstance ?: return

        // Hit-test the middle of the screen against tracked horizontal planes.
        // If there's no suitable plane yet, we'll simply try again on the next
        // frame once ARCore has more data.
        // If we have persisted placement data, try to hit-test near the last
        // user's tapped/placed point. Otherwise, fall back to screen-centre.
        val useSavedPlacement = restoreIsPlaced &&
            restoreHitXNorm != null &&
            restoreHitYNorm != null &&
            restorePlacementFailedFrames < 60

        val targetX = if (useSavedPlacement) {
            arSceneView.width * restoreHitXNorm!!
        } else {
            arSceneView.width / 2.0f
        }

        val targetY = if (useSavedPlacement) {
            arSceneView.height * restoreHitYNorm!!
        } else {
            arSceneView.height / 2.0f
        }

        val hit: HitResult? = hitTestFloor(targetX, targetY)

        if (hit == null) {
            if (useSavedPlacement) restorePlacementFailedFrames += 1
            return
        }

        // Remember the normalized placement point for persistence.
        if (arSceneView.width > 0 && arSceneView.height > 0) {
            lastHitXNorm = targetX / arSceneView.width
            lastHitYNorm = targetY / arSceneView.height
        }

        placeAnchoredModel(hit, instance)
    }

    /**
     * Creates an anchored node at the given ARCore [HitResult] and attaches a
     * gesture‑editable [ModelNode] built from the provided [ModelInstance].
     */
    private fun placeAnchoredModel(hitResult: HitResult, instance: ModelInstance) {
        // Build an AnchorNode locked to the plane pose we just hit. The node
        // keeps itself in sync with ARCore as tracking refines over time.
        val anchorNode = AnchorNode(
            engine = arSceneView.engine,
            anchor = hitResult.createAnchor()
        ).also { configurePlacedAnchorNode(it) }

        // Wrap the loaded model into a SceneView [ModelNode] so it can live in
        // the node graph and participate in the gesture system.
        val modelNode = YawLimitedModelNode(modelInstance = instance).apply {
            // Opt this node into SceneView's built‑in editing pipeline so users
            // can drag, scale and rotate it directly on top of the anchor.
            isEditable = true
            isPositionEditable = false
            isRotationEditable = true
            isScaleEditable = true
            editableScaleRange = 0.3f..4.0f

            // Apply the base scale (if provided by Flutter) so that the starting
            // size reflects any product‑level calibration before gestures.
            val base = safeBaseScale(modelBaseScale)
            scale = Scale(base, base, base)

            // If we restored a previous placement session, restore the user's
            // saved per-axis scale and yaw as well.
            val restored = restoreScale
            if (restored != null) {
                scale = Scale(
                    x = restored.x.coerceIn(0.3f, 4.0f),
                    y = restored.y.coerceIn(0.3f, 4.0f),
                    z = restored.z.coerceIn(0.3f, 4.0f)
                )
            }

            val restoredYaw = restoreYaw
            if (restoredYaw != null) {
                rotation = Rotation(x = 0f, y = restoredYaw, z = 0f)
            }

            val rp = restorePosition
            if (rp != null) {
                // Keep horizontal drag offset only; Y is always derived from floor contact.
                position = Position(
                    x = rp.x.coerceIn(-8f, 8f),
                    y = 0f,
                    z = rp.z.coerceIn(-8f, 8f),
                )
                restorePosition = null
            }

            configureArShadows()
            seatOnFloorAnchor()
        }

        // Attach the model under the anchor, then add the anchor into the
        // ARSceneView's node hierarchy so it becomes visible and interactive.
        anchorNode.addChildNode(modelNode)
        arSceneView.addChildNode(anchorNode)

        // Keep track of what we've placed so we don't try to auto-place again.
        this.anchorNode = anchorNode
        this.modelNode = modelNode
        modelNode.isVisible = true
        enableArShadowRendering()
        isModelTransformLocked = false
        applyModelTransformLockState()
        // Refresh the overlay so users immediately see an accurate scale/size
        // read‑out once the model appears in the scene.
        updateScaleAndSizeLabels()
        updateProductNameLabel()

        // Persist the restored placement as soon as it's available.
        maybePersistUserEdits()

        // How‑to banner only matters until the user sees the model in the scene.
        runOnUiThread { dismissArTipsBanner() }
    }

    /**
     * Re-anchors an existing [YawLimitedModelNode] onto a new plane hit by
     * creating a fresh [AnchorNode], moving the model under it, and removing
     * the old anchor from the scene. Rotation and scale on the model are
     * preserved.
     */
    private fun reanchorModel(
        hitResult: HitResult,
        currentModelNode: YawLimitedModelNode,
        currentAnchorNode: AnchorNode
    ) {
        // Clear horizontal drag offset; vertical offset comes from floor seating.
        currentModelNode.position = Position(0f, 0f, 0f)
        currentModelNode.seatOnFloorAnchor()
        currentModelNode.configureArShadows()

        val newAnchorNode = AnchorNode(
            engine = arSceneView.engine,
            anchor = hitResult.createAnchor()
        ).also { configurePlacedAnchorNode(it) }

        currentAnchorNode.removeChildNode(currentModelNode)
        arSceneView.removeChildNode(currentAnchorNode)
        try {
            currentAnchorNode.anchor.detach()
        } catch (_: Throwable) {
        }
        try {
            currentAnchorNode.destroy()
        } catch (_: Throwable) {
        }

        newAnchorNode.addChildNode(currentModelNode)
        arSceneView.addChildNode(newAnchorNode)

        anchorNode = newAnchorNode
        modelNode = currentModelNode

        // Re‑anchoring preserves the current scale; we still refresh the labels
        // so that any future UI we add that depends on anchor state stays in
        // sync with what the user sees.
        updateScaleAndSizeLabels()

        // Persist after moving the anchor so the last known pose survives
        // leaving/re-entering the editor.
        maybePersistUserEdits()
    }

    // --------------------------------------------------------------------
    // 6. Scale helpers + overlay label updates
    // --------------------------------------------------------------------

    /**
     * Clamps drag offset (meters, parent/anchor space) so corrupt prefs cannot
     * explode the scene graph.
     */
    private fun safeBaseScale(d: Double): Float {
        val v = if (d.isFinite()) d.toFloat() else 1.0f
        return v.coerceIn(0.3f, 4.0f)
    }

    private fun clampLocalPosition(p: Position): Position {
        // If prefs are corrupted (NaN / Infinity), SceneView transforms can become
        // invalid and crash later in the frame loop.
        if (!p.x.isFinite() || !p.y.isFinite() || !p.z.isFinite()) {
            return Position(0f, 0f, 0f)
        }
        val lim = 8f
        // Anti-floating pass (3/3): keep the model seated on the plane.
        // We still allow X/Z drag, but collapse small Y drift back to 0.
        val y = if (kotlin.math.abs(p.y) < 0.05f) 0f else p.y.coerceIn(-0.05f, 0.05f)
        return Position(
            x = p.x.coerceIn(-lim, lim),
            y = y,
            z = p.z.coerceIn(-lim, lim)
        )
    }

    private fun resetScaleToBase() {
        if (isModelTransformLocked) return
        val node = modelNode ?: return
        val base = safeBaseScale(modelBaseScale)
        val current = node.scale
        val newScale = Scale(base, base, base)
        if (newScale != current) {
            node.scale = newScale
            updateScaleAndSizeLabels()
            maybePersistUserEdits()
        }
    }

    /**
     * Always load the product the user tapped on the card — not a gallery pick from
     * a prior session and not variants[0] (sorted by date).
     */
    private fun applyTappedProductAsActiveModel() {
        val tappedId = initialProductId?.trim().orEmpty()
        if (tappedId.isNotEmpty() && variantProducts.isNotEmpty()) {
            val idx = variantProducts.indexOfFirst { it.productId == tappedId }
            if (idx >= 0) {
                selectedVariantIndex = idx
                applyVariantFields(variantProducts[idx])
                return
            }
        }

        // Fallback: keep Intent extras from Flutter (already on modelSrc / dimensions).
        if (variantProducts.isNotEmpty()) {
            val intentSrc = modelSrc?.trim().orEmpty()
            val bySrc = if (intentSrc.isNotEmpty()) {
                variantProducts.indexOfFirst { it.modelSrc == intentSrc }
            } else {
                -1
            }
            if (bySrc >= 0) {
                selectedVariantIndex = bySrc
                applyVariantFields(variantProducts[bySrc])
            }
        }
    }

    private fun applyVariantFields(variant: VariantProduct) {
        modelSrc = variant.modelSrc
        altText = variant.name
        realWidthMeters = variant.realWidthMeters
        realHeightMeters = variant.realHeightMeters
        realDepthMeters = variant.realDepthMeters
        modelBaseScale = variant.modelBaseScale
    }

    /** Restores last placement pose/scale for this product — not a different gallery model. */
    private fun loadRestoredPlacementState() {
        val keyBase = initialProductId?.let { "ar_editor_state_$it" } ?: "ar_editor_state_unknown"

        restoreIsPlaced = prefs.getBoolean("${keyBase}.isPlaced", false)
        if (!restoreIsPlaced) return

        val hx = prefs.getFloat("${keyBase}.hitXNorm", Float.NaN)
        val hy = prefs.getFloat("${keyBase}.hitYNorm", Float.NaN)
        restoreHitXNorm = if (hx.isNaN() || !hx.isFinite()) null else hx
        restoreHitYNorm = if (hy.isNaN() || !hy.isFinite()) null else hy

        val sx = prefs.getFloat("${keyBase}.scaleX", Float.NaN)
        val sy = prefs.getFloat("${keyBase}.scaleY", Float.NaN)
        val sz = prefs.getFloat("${keyBase}.scaleZ", Float.NaN)
        restoreScale = if (sx.isNaN() || sy.isNaN() || sz.isNaN() || !sx.isFinite() || !sy.isFinite() || !sz.isFinite()) {
            null
        } else {
            Scale(sx, sy, sz)
        }

        val yaw = prefs.getFloat("${keyBase}.yaw", Float.NaN)
        restoreYaw = if (yaw.isNaN() || !yaw.isFinite()) null else yaw

        val px = prefs.getFloat("${keyBase}.posX", Float.NaN)
        val pz = prefs.getFloat("${keyBase}.posZ", Float.NaN)
        restorePosition = if (px.isNaN() || pz.isNaN() || !px.isFinite() || !pz.isFinite()) {
            null
        } else {
            Position(x = px.coerceIn(-8f, 8f), y = 0f, z = pz.coerceIn(-8f, 8f))
        }
    }

    private fun maybePersistUserEdits(force: Boolean = false) {
        val node = modelNode ?: return
        val hitX = lastHitXNorm ?: return
        val hitY = lastHitYNorm ?: return
        val variantProductId = variantProducts.getOrNull(selectedVariantIndex)?.productId

        // Avoid hammering SharedPreferences every frame; only persist on change
        // (or force) with a tiny time throttle for gesture-heavy updates.
        val nowMs = SystemClock.elapsedRealtime()
        val currentScale = node.scale
        val currentYaw = node.rotation.y
        val currentPos = node.position
        // Never persist invalid transforms; they can break restore and crash later.
        if (!currentScale.x.isFinite() || !currentScale.y.isFinite() || !currentScale.z.isFinite() ||
            !currentYaw.isFinite() ||
            !currentPos.x.isFinite() || !currentPos.y.isFinite() || !currentPos.z.isFinite()
        ) {
            return
        }
        val changed = force ||
            lastPersistedScale == null ||
            kotlin.math.abs((lastPersistedScale?.x ?: 0f) - currentScale.x) > 0.0001f ||
            kotlin.math.abs((lastPersistedScale?.y ?: 0f) - currentScale.y) > 0.0001f ||
            kotlin.math.abs((lastPersistedScale?.z ?: 0f) - currentScale.z) > 0.0001f ||
            kotlin.math.abs((lastPersistedYaw ?: 0f) - currentYaw) > 0.01f ||
            lastPersistedPosition == null ||
            kotlin.math.abs((lastPersistedPosition?.x ?: 0f) - currentPos.x) > 0.0001f ||
            kotlin.math.abs((lastPersistedPosition?.y ?: 0f) - currentPos.y) > 0.0001f ||
            kotlin.math.abs((lastPersistedPosition?.z ?: 0f) - currentPos.z) > 0.0001f ||
            lastPersistedVariantProductId != variantProductId
        if (!force && !changed) return
        if (!force && (nowMs - lastPersistAtMs) < 250L) return

        val keyBase = initialProductId?.let { "ar_editor_state_$it" } ?: "ar_editor_state_unknown"

        prefs.edit()
            .putBoolean("${keyBase}.isPlaced", true)
            .putFloat("${keyBase}.hitXNorm", hitX)
            .putFloat("${keyBase}.hitYNorm", hitY)
            .putFloat("${keyBase}.scaleX", currentScale.x)
            .putFloat("${keyBase}.scaleY", currentScale.y)
            .putFloat("${keyBase}.scaleZ", currentScale.z)
            .putFloat("${keyBase}.yaw", currentYaw)
            .putFloat("${keyBase}.posX", currentPos.x)
            .putFloat("${keyBase}.posY", currentPos.y)
            .putFloat("${keyBase}.posZ", currentPos.z)
            .putString("${keyBase}.variantProductId", variantProductId)
            .apply()

        lastPersistedScale = Scale(currentScale.x, currentScale.y, currentScale.z)
        lastPersistedYaw = currentYaw
        lastPersistedPosition = Position(currentPos.x, currentPos.y, currentPos.z)
        lastPersistedVariantProductId = variantProductId
        lastPersistAtMs = nowMs
    }

    /**
     * Updates the overlay labels to reflect the current node scale and, when
     * real‑world dimensions are available, an approximate live size.
     */
    private fun updateScaleAndSizeLabels() {
        val node = modelNode ?: return
        if (Looper.myLooper() != Looper.getMainLooper()) {
            runOnUiThread { updateScaleAndSizeLabels() }
            return
        }

        val s = node.scale
        val uniform = ((s.x + s.y + s.z) / 3f).coerceIn(0.3f, 4.0f)

        scaleFactorLabel?.text = String.format("%.2f×", uniform)

        val w = realWidthMeters
        val h = realHeightMeters
        val d = realDepthMeters

        if (w != null || h != null || d != null) {
            val width = w?.times(s.x.toDouble())
            val height = h?.times(s.y.toDouble())
            val depth = d?.times(s.z.toDouble())
            val wText = width?.let { String.format("W:%.2fm", it) } ?: "—"
            val hText = height?.let { String.format("H:%.2fm", it) } ?: "—"
            val dText = depth?.let { String.format("D:%.2fm", it) } ?: "—"
            dimensionsLabel?.text = "$wText  $hText  $dText"
        } else {
            dimensionsLabel?.text = "—"
        }

        isSyncingSlidersFromModel = true
        scaleSeekBar?.progress = scaleToSeekProgress(uniform)
        val yaw = ((node.rotation.y % 360f) + 360f) % 360f
        rotationSeekBar?.progress = yaw.roundToInt().coerceIn(0, 360)
        isSyncingSlidersFromModel = false
    }

    override fun onDestroy() {
        if (isVideoRecording) stopVideoRecording()
        dismissArTipsBanner()
        super.onDestroy()
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

