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
import android.graphics.Rect
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.PixelCopy
import android.text.TextUtils
import android.view.View
import android.view.View.MeasureSpec
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.HorizontalScrollView
import android.widget.ScrollView
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
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.math.Position
import io.github.sceneview.math.Scale
import io.github.sceneview.math.Rotation
import io.github.sceneview.model.ModelInstance
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
    private var restoreVariantProductId: String? = null
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
    /** Circular frame wrappers for variant thumbnails (selection ring). */
    private val variantThumbFrames: MutableList<FrameLayout> = mutableListOf()
    private var variantSwapRequestId: Int = 0

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
    private var scaleLabel: TextView? = null
    private var sizeLabel: TextView? = null
    private var overlayProductNameLabel: TextView? = null
    private var overlayContent: LinearLayout? = null
    private var isOverlayExpanded: Boolean = true
    private var scaleOverlayWidthPx: Int = 0
    private var scaleOverlayContainer: LinearLayout? = null
    private var scaleScrollView: ScrollView? = null
    private var variantCarouselContainer: View? = null
    private var igVariantCarouselHeightPx: Int = 0
    private var hiddenActionsBar: FrameLayout? = null
    private var overlaysVisible: Boolean = true
    private var overlaysEyeButton: ImageButton? = null

    /** Short AR how‑to; hidden as soon as the model is anchored in the scene. */
    private var arTipsBanner: TextView? = null

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

            // Optional Option A payload: list of same-category variants.
            val variantsJson = extras.getString("variantProductsJson")
            initialProductId = extras.getString("initialProductId")

            variantProducts = parseVariantsJson(variantsJson)
            if (initialProductId != null) {
                val idx = variantProducts.indexOfFirst { it.productId == initialProductId }
                if (idx >= 0) selectedVariantIndex = idx
            }

            // Load persisted placement+scale state (if any).
            loadRestoredStateAndApplyToFields()
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

                // Re-enable environmental HDR so indirect light + reflections
                // match the real room better (ambient-only looked too dark).
                config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
            }

            // Once per ARCore frame, if we have a loaded model and haven't
            // placed it yet, try to auto-place it on the first tracked
            // horizontal plane under the screen centre. This makes the product
            // appear automatically at 100% size when the scene opens.
            onSessionUpdated = { _: Session, _ ->
                try {
                    tryAutoPlaceModel()
                    // Keep overlay labels/persistence in sync with gesture edits
                    // (drag/pinch/rotate) that don't pass through our +/- handlers.
                    updateScaleAndSizeLabels()
                    maybePersistUserEdits()
                } catch (t: Throwable) {
                    // Prevent hard crashes from non-fatal UI/persistence issues.
                    Log.e("ArEditorActivity", "onSessionUpdated crash guard", t)
                }
            }

            // Allow the user to re-anchor the already placed model by tapping
            // on another horizontal plane. We keep rotation/scale on the
            // existing node and simply move it under a new AnchorNode.
            onTouchEvent = { motionEvent: MotionEvent, _ ->
                if (motionEvent.action == MotionEvent.ACTION_UP) {
                    val instance = modelInstance
                    val currentModel = modelNode
                    val currentAnchor = anchorNode
                    if (instance != null && currentModel != null && currentAnchor != null) {
                        val hit: HitResult? = hitTestAR(
                            xPx = motionEvent.x,
                            yPx = motionEvent.y,
                            planeTypes = setOf(Plane.Type.HORIZONTAL_UPWARD_FACING)
                        )
                        if (hit != null) {
                            // Persist the last "point X" as a normalized screen
                            // coordinate so restoring works across orientation changes.
                            if (arSceneView.width > 0 && arSceneView.height > 0) {
                                lastHitXNorm = motionEvent.x / arSceneView.width
                                lastHitYNorm = motionEvent.y / arSceneView.height
                            }
                            reanchorModel(hit, currentModel, currentAnchor)
                        }
                    }
                }
                // Return false so that ARSceneView's internal gesture system
                // (scale/rotate) still receives the event stream.
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

        // Build and attach a minimal overlay toolbar that:
        // - Surfaces a readable scale + size status.
        // - Provides explicit +/- buttons as an alternative to pinch gesture.
        // - Gives short AR usage hints that work in both portrait & landscape.
        attachOverlayToolbar(rootLayout)

        // Option A: bottom-left variant carousel (left side in both orientations).
        attachVariantCarouselPlaceholder(rootLayout)

        // Center-top AR usage tips (dismissed once the model is placed).
        attachArTipsBanner(rootLayout)

        // One-button toggle: hide/show BOTH overlays together.
        attachOverlaysEyeToggleButton(rootLayout)
        // Bottom utility actions appear only when overlays are hidden.
        attachHiddenActionsBar(rootLayout)

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
        // 5. Kick off background model loading for tap‑to‑place.
        // --------------------------------------------------------------------
        //
        // We resolve the GLB referenced by [modelSrc] using SceneView's
        // built‑in [ModelLoader]. Once loaded, taps can reuse this single
        // [ModelInstance] and attach it to new anchors instantly.
        preloadModelInstance()
    }

    /**
     * Constructs a small, bottom‑anchored overlay toolbar with:
     * - Live labels for per‑axis scale + approximate real‑world dimensions.
     * - Quantity‑style +/- controls for Width, Height, Depth.
     * - A Reset button to snap back to the calibrated base scale.
     * - A collapsible body so the chrome can get out of the way when not
     *   needed.
     *
     * The layout uses match‑parent width and wraps its height so it adapts
     * gracefully to both portrait and landscape orientations.
     */
    private fun attachOverlayToolbar(root: FrameLayout) {
        fun dpToPx(dp: Int): Int {
            return (dp * resources.displayMetrics.density).roundToInt()
        }

        // IG-style: start collapsed (label only). Expands to show size/scale controls.
        isOverlayExpanded = false

        // Outer container that floats above the camera feed (elevation helps it
        // stay visually above the GL/Surface layer on some devices).
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            // Keep horizontal padding balanced and slightly roomier.
            setPadding(16, 8, 16, 10)
            background = ContextCompat.getDrawable(
                this@ArEditorActivity,
                R.drawable.bg_ar_panel_rounded_border
            )
            elevation = 12f
        }
        scaleOverlayContainer = container

        // Collapsed IG-style bottom button row:
        // - left: Gallery
        // - center: model name (tap expands size/scale controls)
        // - right: Preview
        val igRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, 4)
        }

        fun createIgIconButton(iconResId: Int, contentDesc: String, onClick: () -> Unit): ImageButton {
            val btnSize = dpToPx(44)
            return ImageButton(this).apply {
                setImageDrawable(ContextCompat.getDrawable(this@ArEditorActivity, iconResId))
                background =
                    ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_action_circle_transparent)
                setBackgroundColor(0x00000000)
                minimumWidth = btnSize
                minimumHeight = btnSize
                setPadding(dpToPx(10), dpToPx(10), dpToPx(10), dpToPx(10))
                contentDescription = contentDesc
                setOnClickListener { onClick() }
            }
        }

        val mainExpandButton = FrameLayout(this).apply {
            // This is the "size + scale button" in IG style.
            background = ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_overlay_control)
            setPadding(dpToPx(16), dpToPx(10), dpToPx(16), dpToPx(10))
            // Rounded "pill-ish" look comes from bg drawable.
            setOnClickListener {
                isOverlayExpanded = !isOverlayExpanded
                scaleScrollView?.visibility = if (isOverlayExpanded) View.VISIBLE else View.GONE
            }
        }

        overlayProductNameLabel = TextView(this).apply {
            text = currentOverlayProductName()
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 13f
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            gravity = Gravity.CENTER_HORIZONTAL
        }

        mainExpandButton.addView(
            overlayProductNameLabel,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_HORIZONTAL
            )
        )

        // Only the model pill is inside the overlay.
        // Gallery + Preview are pinned outside the overlay (bottom-left / bottom-right).
        igRow.addView(
            mainExpandButton,
            LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            )
        )

        container.addView(igRow)

        // Collapsible body that holds labels + per‑axis controls. We'll wrap
        // this in a ScrollView with an explicit max height so the entire
        // overlay never occupies more than ~20% of the screen on modern
        // Android devices.
        overlayContent = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 6, 0, 0)
        }

        // First row inside body: scale + size labels.
        scaleLabel = TextView(this).apply {
            text = "Scale: W 1.00×  ·  H 1.00×  ·  D 1.00×"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 14f
            gravity = Gravity.CENTER_HORIZONTAL
        }
        sizeLabel = TextView(this).apply {
            text = "Size: —"
            setTextColor(0xFFDDDDDD.toInt())
            textSize = 12f
            gravity = Gravity.CENTER_HORIZONTAL
        }

        overlayContent?.addView(scaleLabel)
        overlayContent?.addView(sizeLabel)

        // Helper to build a quantity‑style +/- control row for a single axis.
        fun createAxisRow(
            label: String,
            onDecrease: () -> Unit,
            onIncrease: () -> Unit
        ): LinearLayout {
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, 4, 0, 4)
            }

            val axisLabel = TextView(this).apply {
                text = label
                setTextColor(0xFFEEEEEE.toInt())
                textSize = 12f
            }

            val minusButton = Button(this).apply {
                text = "−"
                textSize = 18f
                setAllCaps(false)
                // Wider tap targets, slightly shorter vertical footprint.
                minimumWidth = dpToPx(52)
                minHeight = dpToPx(36)
                setPadding(22, 4, 22, 4)
                setTextColor(0xFFFFFFFF.toInt())
                background =
                    ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_overlay_control)
                setOnClickListener { onDecrease() }
            }

            val plusButton = Button(this).apply {
                text = "+"
                textSize = 18f
                setAllCaps(false)
                minimumWidth = dpToPx(52)
                minHeight = dpToPx(36)
                setPadding(22, 4, 22, 4)
                setTextColor(0xFFFFFFFF.toInt())
                background =
                    ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_overlay_control)
                setOnClickListener { onIncrease() }
            }

            row.addView(
                axisLabel,
                LinearLayout.LayoutParams(
                    0,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    1f
                )
            )

            val btnParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginStart = 6
            }

            row.addView(minusButton, btnParams)
            row.addView(plusButton, btnParams)

            return row
        }

        // Width row: adjusts X scale only.
        val widthRow = createAxisRow(
            label = "Width",
            onDecrease = { applyWidthDelta(0.9f) },
            onIncrease = { applyWidthDelta(1.1f) }
        )

        // Height row: adjusts Y scale only.
        val heightRow = createAxisRow(
            label = "Height",
            onDecrease = { applyHeightDelta(0.9f) },
            onIncrease = { applyHeightDelta(1.1f) }
        )

        // Depth row: adjusts Z scale only.
        val depthRow = createAxisRow(
            label = "Depth",
            onDecrease = { applyDepthDelta(0.9f) },
            onIncrease = { applyDepthDelta(1.1f) }
        )

        overlayContent?.addView(widthRow)
        overlayContent?.addView(heightRow)
        overlayContent?.addView(depthRow)

        // Reset centered under the axis rows so the stack feels balanced in the card.
        val resetButton = Button(this).apply {
            text = "Reset all"
            textSize = 13f
            setAllCaps(false)
            setPadding(18, 6, 18, 6)
            setTextColor(0xFFFFFFFF.toInt())
            background =
                ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_overlay_control)
            setOnClickListener { resetScaleToBase() }
        }

        val resetRow = FrameLayout(this).apply {
            setPadding(0, 4, 0, 4)
        }
        resetRow.addView(
            resetButton,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_HORIZONTAL
            )
        )

        overlayContent?.addView(resetRow)

        // Scroll area: when expanded, it should occupy at least ~25% of the screen
        // height so the controls feel "full" (IG bottom-sheet vibe).
        val screenH = resources.displayMetrics.heightPixels
        val maxBodyPx = (screenH * 0.25f).toInt()
            .coerceAtLeast(dpToPx(220))
            .coerceAtMost(dpToPx(520))
        val scrollView = CappedHeightScrollView(this).apply {
            maxHeightPx = maxBodyPx
            // When expanded, keep a consistent "IG sheet" height feel even if
            // content doesn't fill it completely.
            minimumHeight = maxBodyPx
            isFillViewport = false
            overScrollMode = ScrollView.OVER_SCROLL_IF_CONTENT_SCROLLS
        }
        scaleScrollView = scrollView
        scrollView.addView(
            overlayContent,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
        )

        container.addView(
            scrollView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        // Start collapsed: label only.
        scrollView.visibility = if (isOverlayExpanded) View.VISIBLE else View.GONE

        // Width: prefer ~48% of screen but shrink when the variant carousel
        // needs a fixed 3-column strip so panels never overlap.
        val overlayWidthPx = computeOverlayWidthPx()
        scaleOverlayWidthPx = overlayWidthPx

        val layoutParams = FrameLayout.LayoutParams(
            overlayWidthPx,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            marginStart = dpToPx(16)
            marginEnd = dpToPx(16)
            bottomMargin = dpToPx(24)
        }

        root.addView(container, layoutParams)
    }

    /**
     * Fixed outer width for the **vertical** variant column (single circle width
     * + horizontal padding). Must match [attachVariantCarouselPlaceholder].
     */
    private fun computeVariantCarouselOuterWidthPx(): Int {
        fun dp(dp: Int): Int = (dp * resources.displayMetrics.density).roundToInt()
        // One 48dp thumbnail + 8dp padding each side (border is inside drawable).
        return dp(48 + 8 * 2)
    }

    /**
     * Computes scale overlay width (IG-style bottom pill). The carousel now
     * lives at the bottom center, so we don't reserve left-side space anymore.
     */
    private fun computeOverlayWidthPx(): Int {
        fun dp(dp: Int): Int = (dp * resources.displayMetrics.density).roundToInt()
        val screenW = resources.displayMetrics.widthPixels
        val isLandscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val marginStart = dp(if (isLandscape) 28 else 16)
        val marginEnd = dp(if (isLandscape) 56 else 16)

        // Reserve space on both sides for Gallery (left) and Preview (right)
        // so the center overlay pill doesn't visually collide with them.
        val sideReserve = dp(if (isLandscape) 96 else 88)

        val desired = (screenW * 0.53f).toInt().coerceIn(dp(300), dp(440))

        val maxForScale = screenW - marginStart - marginEnd - (sideReserve * 2)
        return desired.coerceAtMost(maxForScale.coerceAtLeast(dp(200)))
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

            scaleOverlayContainer?.let { v ->
                (v.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                    lp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                    val screenW = resources.displayMetrics.widthPixels
                    // Carousel sits ABOVE the overlay pill (IG-style stacking).
                    // So the overlay should not reserve carousel space.
                    lp.bottomMargin = insetBottom + dp(16)
                    lp.marginStart = insetStart + dp(16)
                    lp.marginEnd = insetEnd + dp(16)
                    val availableW = (screenW - lp.marginStart - lp.marginEnd).coerceAtLeast(dp(200))
                    lp.width = scaleOverlayWidthPx.coerceAtMost(availableW)
                    v.layoutParams = lp
                }
            }
            variantCarouselContainer?.let { v ->
                (v.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                    lp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                    // Keep carousel centered; don't reserve left/right safe areas here.
                    lp.marginStart = 0
                    lp.marginEnd = 0
                    lp.topMargin = 0
                    // Push carousel above the overlay pill.
                    lp.bottomMargin = insetBottom + dp(48)
                    // Keep the IG viewport width set in attachVariantCarouselPlaceholder().
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
            arTipsBanner?.let { v ->
                (v.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                    lp.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                    lp.topMargin = insetTop + dp(8)
                    lp.marginStart = insetStart + dp(20)
                    lp.marginEnd = insetEnd + dp(20)
                    v.layoutParams = lp
                }
            }
            hiddenActionsBar?.let { v ->
                (v.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                    val screenW = resources.displayMetrics.widthPixels
                    val availableW = (screenW - insetStart - insetEnd).coerceAtLeast(dp(200))
                    val isLandscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
                    val sideReserve = dp(if (isLandscape) 96 else 88)
                    val overlayW = if (scaleOverlayWidthPx > 0) scaleOverlayWidthPx else (screenW * 0.53f).toInt()
                    // Bar width spans overlay pill + reserved sides so icons sit inline.
                    val barW = (overlayW + (sideReserve * 2)).coerceAtMost(availableW)

                    lp.width = barW
                    lp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                    lp.marginStart = 0
                    lp.marginEnd = 0
                    lp.bottomMargin = insetBottom + dp(12)
                    v.layoutParams = lp
                }
            }
            insets
        }
        ViewCompat.requestApplyInsets(root)
    }

    /**
     * Short, centered guidance under the status bar. Removed automatically when
     * [placeAnchoredModel] runs so it never fights the scale / variant chrome.
     */
    private fun attachArTipsBanner(root: FrameLayout) {
        fun dpToPx(dp: Int): Int =
            (dp * resources.displayMetrics.density).roundToInt()

        val screenW = resources.displayMetrics.widthPixels
        val maxTextW = (screenW * 0.68f).toInt()

        val tv = TextView(this).apply {
            text =
                "Point at a horizontal surface — the model places when AR locks on. " +
                    "Drag to move, pinch to scale, two fingers to rotate."
            setTextColor(0xFFF5F5F5.toInt())
            textSize = 13f
            setLineSpacing(dpToPx(2).toFloat(), 1f)
            setPadding(dpToPx(16), dpToPx(12), dpToPx(16), dpToPx(12))
            gravity = Gravity.CENTER_HORIZONTAL
            this.maxWidth = maxTextW
            // Transparent tips card per latest UI request (no border).
            setBackgroundColor(0x00000000)
        }
        arTipsBanner = tv

        val lp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dpToPx(30)
            marginStart = dpToPx(16)
            marginEnd = dpToPx(16)
        }
        root.addView(tv, lp)
    }

    private fun dismissArTipsBanner() {
        arTipsBanner?.visibility = View.GONE
        arTipsBanner = null
    }

    private fun currentOverlayProductName(): String {
        return variantProducts.getOrNull(selectedVariantIndex)?.name
            ?: altText
            ?: "Current model"
    }

    private fun updateOverlayProductNameLabel() {
        overlayProductNameLabel?.text = currentOverlayProductName()
    }

    /**
     * IG-style **horizontal** variant carousel:
     * - Swipe to change the selected variant.
     * - The selected variant is always snapped to the center.
     * - The centered position acts as the "camera" button (capture on tap).
     */
    private fun attachVariantCarouselPlaceholder(root: FrameLayout) {
        fun dpToPx(dp: Int): Int = (dp * resources.displayMetrics.density).roundToInt()
        if (variantProducts.isEmpty()) return

        val thumbSizePx = dpToPx(60)
        val thumbInsetPx = dpToPx(4)
        val itemGapPx = dpToPx(14)

        // Fixed height so the overlay above it can reserve space.
        igVariantCarouselHeightPx = dpToPx(100)
        // IG-style: show 3 full circles at once.
        // Selected item + 1 neighbor on each side fit exactly in the viewport width,
        // so the next items are clipped/peeking on the edges.
        val viewportW = thumbSizePx * 3 + itemGapPx * 2

        val container = FrameLayout(this).apply {
            // Intentionally subtle: thumbnails already have their own ring styling.
            setBackgroundColor(0x00000000)
        }
        variantCarouselContainer = container

        val scrollView = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            clipToPadding = false
            isFillViewport = false
        }

        val host = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        scrollView.addView(
            host,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        // Center "camera" tap target.
        val cameraOverlay = ImageButton(this).apply {
            setImageDrawable(ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.ic_ar_camera))
            background = ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_action_circle_transparent)
            setBackgroundColor(0x00000000)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            adjustViewBounds = true
            minimumWidth = thumbSizePx
            minimumHeight = thumbSizePx
            setPadding(dpToPx(14), dpToPx(14), dpToPx(14), dpToPx(14))
            contentDescription = "Capture AR screen"
            setOnClickListener { captureArScreenshot() }
        }

        container.addView(
            scrollView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        container.addView(
            cameraOverlay,
            FrameLayout.LayoutParams(
                thumbSizePx,
                thumbSizePx,
                Gravity.CENTER
            )
        )

        variantThumbFrames.clear()

        // Local helpers must be declared before they are first used.
        fun scrollToVariantIndex(index: Int, smooth: Boolean) {
            if (index !in variantThumbFrames.indices) return
            val thumb = variantThumbFrames[index]
            val targetX = (thumb.left + thumb.width / 2) - scrollView.width / 2
            val maxX = (host.width - scrollView.width).coerceAtLeast(0)
            val clampedX = targetX.coerceIn(0, maxX)
            if (smooth) scrollView.smoothScrollTo(clampedX, 0) else scrollView.scrollTo(clampedX, 0)
            if (index != selectedVariantIndex) {
                selectedVariantIndex = index
                updateVariantThumbnailStyles()
                swapVariantModel(variantIndex = index)
            }
        }

        fun findClosestCenteredIndex(
            scroll: HorizontalScrollView
        ): Int? {
            if (variantThumbFrames.isEmpty()) return null
            val scrollCenter = scroll.scrollX + scroll.width / 2
            var bestIdx = 0
            var bestDist = Int.MAX_VALUE
            variantThumbFrames.forEachIndexed { idx, thumb ->
                val thumbCenter = thumb.left + thumb.width / 2
                val dist = kotlin.math.abs(thumbCenter - scrollCenter)
                if (dist < bestDist) {
                    bestDist = dist
                    bestIdx = idx
                }
            }
            return bestIdx
        }

        fun snapToIndex(
            index: Int,
            scroll: HorizontalScrollView,
            containerHost: LinearLayout
        ) {
            if (index !in variantThumbFrames.indices) return
            val thumb = variantThumbFrames[index]
            val targetX = (thumb.left + thumb.width / 2) - scroll.width / 2
            val maxX = (containerHost.width - scroll.width).coerceAtLeast(0)
            val clampedX = targetX.coerceIn(0, maxX)
            scroll.smoothScrollTo(clampedX, 0)
        }

        variantProducts.forEachIndexed { idx, variant ->
            val frame = FrameLayout(this).apply {
                layoutParams = LinearLayout.LayoutParams(thumbSizePx, thumbSizePx).apply {
                    if (idx > 0) marginStart = itemGapPx
                }
                background = ContextCompat.getDrawable(
                    this@ArEditorActivity,
                    R.drawable.bg_variant_thumb_unselected
                )
                clipToPadding = false
                setPadding(thumbInsetPx, thumbInsetPx, thumbInsetPx, thumbInsetPx)
            }

            val imageView = ImageView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                scaleType = ImageView.ScaleType.CENTER_CROP
                contentDescription = variant.name
            }

            val url = variant.thumbnailUrl
            if (!url.isNullOrBlank()) {
                imageView.load(url) {
                    crossfade(true)
                    transformations(CircleCropTransformation())
                    placeholder(R.drawable.bg_variant_placeholder)
                    error(R.drawable.bg_variant_placeholder)
                }
            } else {
                imageView.setImageResource(R.drawable.bg_variant_placeholder)
            }

            frame.addView(imageView)
            frame.setOnClickListener {
                if (idx == selectedVariantIndex) {
                    // Center spot is reserved for the camera overlay.
                    // Tapping the centered thumbnail should only keep it selected.
                    return@setOnClickListener
                }
                // Snap this variant into the center, then swap the model.
                scrollToVariantIndex(idx, smooth = true)
            }

            host.addView(frame)
            variantThumbFrames.add(frame)
        }

        updateVariantThumbnailStyles()

        // Snap logic: after user stops swiping, find the thumb nearest to center
        // and smooth-scroll to perfectly center it.
        val snapHandler = Handler(Looper.getMainLooper())
        val snapRunnable = Runnable {
            try {
                val closest = findClosestCenteredIndex(scrollView)
                if (closest == null) return@Runnable

                // Smooth snap (ensures the centered variant is always stable).
                snapToIndex(closest, scrollView, host)

                if (closest != selectedVariantIndex) {
                    selectedVariantIndex = closest
                    updateVariantThumbnailStyles()
                    swapVariantModel(variantIndex = closest)
                } else {
                    updateVariantThumbnailStyles()
                }
            } catch (t: Throwable) {
                Log.e("ArEditorActivity", "carousel snap crash guard", t)
            }
        }

        scrollView.setOnScrollChangeListener { _, _, _, _, _ ->
            try {
                snapHandler.removeCallbacks(snapRunnable)
                snapHandler.postDelayed(snapRunnable, 140L)
            } catch (t: Throwable) {
                Log.e("ArEditorActivity", "carousel onScroll guard", t)
            }
        }

        // Center the initially selected variant.
        container.post {
            val pad = (container.width - thumbSizePx) / 2
            host.setPadding(pad, 0, pad, 0)
            scrollToVariantIndex(selectedVariantIndex, smooth = false)
        }

        val layoutParams = FrameLayout.LayoutParams(
            viewportW,
            igVariantCarouselHeightPx
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            // Keep a little air from screen edges.
            val safeInset = dpToPx(12)
            marginStart = safeInset
            marginEnd = safeInset
        }
        root.addView(container, layoutParams)
    }

    /**
     * One-button UX toggle:
     * - When pressed: hides the scale/size overlay AND the variant carousel.
     * - When pressed again: shows them back.
     *
     * The scale overlay's internal "expanded/collapsed" state is preserved
     * (so when we show again, the ScrollView uses [isOverlayExpanded]).
     */
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

                scaleOverlayContainer?.visibility = visibility
                variantCarouselContainer?.visibility = visibility
                // Gallery/Preview should never appear when overlays are hidden.
                hiddenActionsBar?.visibility = if (overlaysVisible) View.VISIBLE else View.GONE
                // Restore scale ScrollView based on the previous expanded state.
                if (overlaysVisible) {
                    scaleScrollView?.visibility = if (isOverlayExpanded) View.VISIBLE else View.GONE
                }

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

    private fun attachHiddenActionsBar(root: FrameLayout) {
        fun dpToPx(dp: Int): Int = (dp * resources.displayMetrics.density).roundToInt()

        val bar = FrameLayout(this).apply {
            // No visible background behind icon buttons (clean, unobtrusive).
            setBackgroundColor(0x00000000)
            elevation = 10f
            visibility = View.GONE
        }

        val btnSizePx = dpToPx(60)
        val itemGapPx = dpToPx(22)

        fun createActionButton(iconResId: Int, contentDesc: String, onClick: () -> Unit): ImageButton {
            return ImageButton(this).apply {
                setImageDrawable(ContextCompat.getDrawable(this@ArEditorActivity, iconResId))
                // Transparent circular touch target: no fill, no border.
                background =
                    ContextCompat.getDrawable(this@ArEditorActivity, R.drawable.bg_ar_action_circle_transparent)
                setBackgroundColor(0x00000000)
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                adjustViewBounds = true
                minimumHeight = btnSizePx
                minimumWidth = btnSizePx
                setPadding(dpToPx(12), dpToPx(12), dpToPx(12), dpToPx(12))
                contentDescription = contentDesc
                setOnClickListener { onClick() }
            }
        }

        fun createActionItem(
            iconResId: Int,
            label: String,
            contentDesc: String,
            onClick: () -> Unit
        ): LinearLayout {
            val item = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
            }

            val iconBtn = createActionButton(iconResId, contentDesc, onClick).apply {
                layoutParams = LinearLayout.LayoutParams(btnSizePx, btnSizePx)
            }

            val name = TextView(this).apply {
                text = label
                textSize = 11f
                setTextColor(0xFFFFFFFF.toInt())
                setPadding(0, dpToPx(6), 0, 0)
                gravity = Gravity.CENTER_HORIZONTAL
            }

            item.addView(iconBtn)
            item.addView(name, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ))
            return item
        }

        val galleryItem = createActionItem(
            R.drawable.ic_ar_gallery,
            "Gallery",
            "Open gallery",
            { openGalleryPicker() }
        )
        val previewItem = createActionItem(
            R.drawable.ic_ar_preview,
            "Preview",
            "Preview model",
            { openModelPreviewActivity() }
        )

        val lpLeft = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.START or Gravity.CENTER_VERTICAL
        ).apply {
            marginStart = dpToPx(6)
        }
        val lpRight = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.END or Gravity.CENTER_VERTICAL
        ).apply {
            marginEnd = dpToPx(6)
        }

        bar.addView(galleryItem, lpLeft)
        bar.addView(previewItem, lpRight)

        hiddenActionsBar = bar

        val lp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            bottomMargin = dpToPx(16)
        }
        root.addView(bar, lp)
    }

    private fun openGalleryPicker() {
        try {
            val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            startActivity(intent)
        } catch (_: Exception) {
            Toast.makeText(this, "Unable to open gallery", Toast.LENGTH_SHORT).show()
        }
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

        hide(scaleOverlayContainer)
        hide(variantCarouselContainer)
        hide(overlaysEyeButton)
        hide(hiddenActionsBar)
        hide(arTipsBanner)

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

    private fun openModelPreviewActivity() {
        val current = variantProducts.getOrNull(selectedVariantIndex)
        val modelSrc = current?.modelSrc
        val name = current?.name ?: altText ?: "Model"

        if (modelSrc.isNullOrBlank()) {
            Toast.makeText(this, "No model available to preview", Toast.LENGTH_SHORT).show()
            return
        }

        val looksLikeHttp = modelSrc.startsWith("http://") || modelSrc.startsWith("https://")
        if (!looksLikeHttp) {
            Toast.makeText(this, "Preview not supported for this model path", Toast.LENGTH_SHORT).show()
            return
        }

        val intent = Intent(this, ModelPreviewActivity::class.java).apply {
            putExtra("modelSrc", modelSrc)
            putExtra("altText", name)
        }
        startActivity(intent)
    }

    private fun updateVariantThumbnailStyles() {
        variantThumbFrames.forEachIndexed { idx, frame ->
            val selected = idx == selectedVariantIndex
            frame.background = ContextCompat.getDrawable(
                this,
                if (selected) R.drawable.bg_variant_thumb_selected else R.drawable.bg_variant_thumb_unselected
            )
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

                list.add(
                    VariantProduct(
                        productId = productId,
                        name = name,
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

    /**
     * Option A: swaps the currently shown model to a different variant.
     *
     * - If the user hasn't placed a model yet, we only preload the new
     *   [modelInstance] so the existing auto-placement will use it.
     * - If a model is already placed, we replace only the child model node
     *   under the current [anchorNode], preserving the AR pose + gestures.
     */
    private fun swapVariantModel(variantIndex: Int) {
        val currentVariant = variantProducts.getOrNull(variantIndex) ?: return
        selectedVariantIndex = variantIndex

        // Bump request id so late async loads don't apply out of order.
        variantSwapRequestId += 1
        val requestIdSnapshot = variantSwapRequestId

        // Capture the user's current per-axis scale when swapping after
        // placement. We want to preserve it so the user doesn't "lose" their
        // custom scaling when they try a new variant.
        val preservedScale: Scale? = modelNode?.scale
        val preservedYaw: Float? = modelNode?.rotation?.y
        val preservedPosition: Position? = modelNode?.position

        // Update labels-related state immediately so the UI feels responsive.
        modelSrc = currentVariant.modelSrc
        altText = currentVariant.name
        realWidthMeters = currentVariant.realWidthMeters
        realHeightMeters = currentVariant.realHeightMeters
        realDepthMeters = currentVariant.realDepthMeters
        modelBaseScale = currentVariant.modelBaseScale
        updateOverlayProductNameLabel()

        // Loading can take time; we only apply if it's still the latest request.
        arSceneView.modelLoader.loadModelInstanceAsync(currentVariant.modelSrc) { instance: ModelInstance? ->
            if (instance == null) return@loadModelInstanceAsync
            if (requestIdSnapshot != variantSwapRequestId) return@loadModelInstanceAsync

            // Case A: no model placed yet -> preload and let auto-place happen.
            if (anchorNode == null || modelNode == null) {
                modelInstance = instance
                tryAutoPlaceModel()
                return@loadModelInstanceAsync
            }

            // Case B: model already placed -> replace the child node under the
            // current anchor so we preserve the AR pose + user gestures.
            val anchor = anchorNode ?: return@loadModelInstanceAsync
            val oldNode = modelNode
            if (oldNode != null) anchor.removeChildNode(oldNode)

            val newNode = YawLimitedModelNode(modelInstance = instance).apply {
                isEditable = true
                isPositionEditable = true
                isRotationEditable = true
                isScaleEditable = true
                editableScaleRange = 0.3f..4.0f

                // Preserve the user's current per-axis scaling across variants.
                // Clamp to the same bounds as the editor to keep UX safe.
                val current = preservedScale
                if (current != null) {
                    val clamped = Scale(
                        x = current.x.coerceIn(0.3f, 4.0f),
                        y = current.y.coerceIn(0.3f, 4.0f),
                        z = current.z.coerceIn(0.3f, 4.0f)
                    )
                    scale = clamped
                } else {
                    // Fallback (should be rare): snap to new product base scale.
                    val base = safeBaseScale(modelBaseScale)
                    scale = Scale(base, base, base)
                }

                // Preserve the previous variant's yaw so swapping variants does
                // not reset the user's chosen facing direction.
                if (preservedYaw != null) {
                    rotation = Rotation(x = 0f, y = preservedYaw, z = 0f)
                }
            }

            anchor.addChildNode(newNode)
            modelNode = newNode
            updateScaleAndSizeLabels()
            maybePersistUserEdits()
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

    /**
     * Starts an asynchronous load of the GLB pointed to by [modelSrc].
     *
     * The load runs on SceneView's internal coroutine scope. Once complete we
     * cache the [ModelInstance] for reuse on future placements.
     */
    private fun preloadModelInstance() {
        val source = modelSrc ?: return

        // SceneView's FileLoader supports multiple sources, but in this
        // integration we *only* treat fully-qualified http/https URLs as
        // loadable. Flutter-style asset paths (assets/...) are not visible to
        // Android's AssetManager by default, and attempting to open them would
        // crash the process with an AssetNotFoundException.
        val looksLikeHttp = source.startsWith("http://") || source.startsWith("https://")
        if (!looksLikeHttp) return

        arSceneView.modelLoader.loadModelInstanceAsync(source) { instance: ModelInstance? ->
            // If loading fails we simply keep [modelInstance] null; taps will
            // then be ignored rather than crashing the Activity.
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

        val hit: HitResult? = arSceneView.hitTestAR(
            xPx = targetX,
            yPx = targetY,
            planeTypes = setOf(Plane.Type.HORIZONTAL_UPWARD_FACING)
        )

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
        )

        // Wrap the loaded model into a SceneView [ModelNode] so it can live in
        // the node graph and participate in the gesture system.
        val modelNode = YawLimitedModelNode(modelInstance = instance).apply {
            // Opt this node into SceneView's built‑in editing pipeline so users
            // can drag, scale and rotate it directly on top of the anchor.
            isEditable = true
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
                position = clampLocalPosition(rp)
                restorePosition = null
            }
        }

        // Attach the model under the anchor, then add the anchor into the
        // ARSceneView's node hierarchy so it becomes visible and interactive.
        anchorNode.addChildNode(modelNode)
        arSceneView.addChildNode(anchorNode)

        // Keep track of what we've placed so we don't try to auto-place again.
        this.anchorNode = anchorNode
        this.modelNode = modelNode

        // Refresh the overlay so users immediately see an accurate scale/size
        // read‑out once the model appears in the scene.
        updateScaleAndSizeLabels()

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
        // Create a new anchor at the tapped pose.
        val newAnchorNode = AnchorNode(
            engine = arSceneView.engine,
            anchor = hitResult.createAnchor()
        )

        // Move the existing model under the new anchor.
        currentAnchorNode.removeChildNode(currentModelNode)
        newAnchorNode.addChildNode(currentModelNode)

        // Swap anchor nodes in the scene graph.
        arSceneView.removeChildNode(currentAnchorNode)
        arSceneView.addChildNode(newAnchorNode)

        // Update our references so future re-anchors use the latest node.
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
     * Adjusts the model's width (X axis) by [factor] while leaving height and
     * depth untouched. Scale is clamped to the same 0.3x–4x range enforced by
     * [YawLimitedModelNode], then the overlay labels are refreshed.
     */
    private fun applyWidthDelta(factor: Float) {
        val node = modelNode ?: return

        val current = node.scale
        val newScale = Scale(
            x = (current.x * factor).coerceIn(0.3f, 4.0f),
            y = current.y,
            z = current.z
        )
        if (newScale != current) {
            node.scale = newScale
            updateScaleAndSizeLabels()
            maybePersistUserEdits()
        }
    }

    /**
     * Adjusts the model's height (Y axis) by [factor] while leaving width and
     * depth untouched.
     */
    private fun applyHeightDelta(factor: Float) {
        val node = modelNode ?: return

        val current = node.scale
        val newScale = Scale(
            x = current.x,
            y = (current.y * factor).coerceIn(0.3f, 4.0f),
            z = current.z
        )
        if (newScale != current) {
            node.scale = newScale
            updateScaleAndSizeLabels()
            maybePersistUserEdits()
        }
    }

    /**
     * Adjusts the model's depth (Z axis) by [factor] while leaving width and
     * height untouched.
     */
    private fun applyDepthDelta(factor: Float) {
        val node = modelNode ?: return

        val current = node.scale
        val newScale = Scale(
            x = current.x,
            y = current.y,
            z = (current.z * factor).coerceIn(0.3f, 4.0f)
        )
        if (newScale != current) {
            node.scale = newScale
            updateScaleAndSizeLabels()
            maybePersistUserEdits()
        }
    }

    /**
     * Resets the model's uniform scale back to the base value supplied from
     * Flutter (`modelBaseScale`), clamped to our safe editing range.
     */
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
        return Position(
            x = p.x.coerceIn(-lim, lim),
            y = p.y.coerceIn(-lim, lim),
            z = p.z.coerceIn(-lim, lim)
        )
    }

    private fun resetScaleToBase() {
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

    private fun loadRestoredStateAndApplyToFields() {
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
        val py = prefs.getFloat("${keyBase}.posY", Float.NaN)
        val pz = prefs.getFloat("${keyBase}.posZ", Float.NaN)
        restorePosition = if (px.isNaN() || py.isNaN() || pz.isNaN() ||
            !px.isFinite() || !py.isFinite() || !pz.isFinite()
        ) {
            null
        } else {
            clampLocalPosition(Position(x = px, y = py, z = pz))
        }

        restoreVariantProductId = prefs.getString("${keyBase}.variantProductId", null)

        // If we restored a different variant, update the initial variant + base
        // scale fields so placement + overlay sizing stay consistent.
        val restoredVariantId = restoreVariantProductId
        if (!restoredVariantId.isNullOrBlank() && variantProducts.isNotEmpty()) {
            val idx = variantProducts.indexOfFirst { it.productId == restoredVariantId }
            if (idx >= 0) {
                selectedVariantIndex = idx
                val variant = variantProducts[idx]
                modelSrc = variant.modelSrc
                realWidthMeters = variant.realWidthMeters
                realHeightMeters = variant.realHeightMeters
                realDepthMeters = variant.realDepthMeters
                modelBaseScale = variant.modelBaseScale
            }
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
        val s = node.scale

        // Scale label: show per‑axis scale factors so people can see which
        // side they have stretched or compressed.
        scaleLabel?.text = String.format(
            "Scale: W %.2fx  ·  H %.2fx  ·  D %.2fx",
            s.x,
            s.y,
            s.z
        )

        // If we know the real‑world dimensions for the product, we can provide
        // a quick approximate "current size" hint so people can reason about
        // fit before committing to a layout.
        val w = realWidthMeters
        val h = realHeightMeters
        val d = realDepthMeters

        if (w != null || h != null || d != null) {
            val width = w?.times(s.x)
            val height = h?.times(s.y)
            val depth = d?.times(s.z)

            val parts = mutableListOf<String>()
            if (width != null) parts += String.format("W %.2fm", width)
            if (height != null) parts += String.format("H %.2fm", height)
            if (depth != null) parts += String.format("D %.2fm", depth)

            sizeLabel?.text = if (parts.isNotEmpty()) {
                "Size: " + parts.joinToString("  ·  ")
            } else {
                "Size: —"
            }
        } else {
            sizeLabel?.text = "Size: real‑world dimensions unavailable"
        }
    }

}

/**
 * Caps vertical size so the scale/size block does not reserve a giant fixed band
 * of the screen; extra rows scroll inside the cap instead.
 */
private class CappedHeightScrollView(context: Context) : ScrollView(context) {
    var maxHeightPx: Int = 0

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        if (maxHeightPx <= 0) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            return
        }
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(maxHeightPx, MeasureSpec.AT_MOST)
        )
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

