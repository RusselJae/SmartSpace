import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:flutter/services.dart';

import '../../services/ar_support_service.dart';
import '../../utils/model_path_helper.dart';
import 'ar_view.dart'; // Import ArModelDimensions

/// =============================================================
/// ArLauncherScreen
///
/// Directly launches Google's ARCore Scene Viewer when opened.
/// Uses JavaScript to automatically trigger the AR button click
/// on the ModelViewer component, launching Scene Viewer immediately.
/// Now includes real-world dimension tracking and automatic scale correction
/// to ensure furniture displays at accurate size in AR.
/// Following Apple's Human Interface Guidelines for a sleek, modern experience.
/// =============================================================
class ArLauncherScreen extends StatefulWidget {
  const ArLauncherScreen({
    super.key,
    required this.modelSrc,
    required this.altText,
    this.realWidthMeters,
    this.realHeightMeters,
    this.realDepthMeters,
    this.modelBaseScale,
  });

  final String modelSrc;
  final String altText;
  final double? realWidthMeters;
  final double? realHeightMeters;
  final double? realDepthMeters;
  final double? modelBaseScale;

  static const String route = '/ar-launcher';

  @override
  State<ArLauncherScreen> createState() => _ArLauncherScreenState();
}

class _ArLauncherScreenState extends State<ArLauncherScreen> {
  final ArSupportService _supportService = ArSupportService.instance;
  bool _resolved = false;
  bool _supportsArCore = false;
  late final String _viewerId;
  ArModelDimensions? _dimensions;
  bool _showGuidance = true; // Show guidance overlay initially
  bool _arLaunched = false; // Track if AR has been launched

  static const String _dimensionChannelName = 'DimensionBridgeLauncher';
  static const MethodChannel _editorChannel = MethodChannel('com.smartspace/ar_editor');

  @override
  void initState() {
    super.initState();
    _viewerId = 'ar-launcher-${widget.modelSrc.hashCode & 0xFFFFFFF}';
    _resolveArSupport();
  }

  /// Check AR capability and determine if Scene Viewer is supported
  Future<void> _resolveArSupport() async {
    final ArCapabilityResult capability = await _supportService.resolveCapability();
    if (!mounted) return;
    setState(() {
      _supportsArCore = capability.enableAr && capability.supportsSceneViewer;
      _resolved = true;
    });
  }

  /// Launches the native AR editor implemented in Kotlin.
  ///
  /// This provides a second, more interactive AR path alongside Google's
  /// Scene Viewer. The editor Activity is intentionally minimal for now and
  /// will evolve as the native ARCore integration grows.
  Future<void> _openNativeEditor() async {
    try {
      await _editorChannel.invokeMethod<void>('openEditor', <String, dynamic>{
        'modelSrc': widget.modelSrc,
        'altText': widget.altText,
        'realWidthMeters': widget.realWidthMeters,
        'realHeightMeters': widget.realHeightMeters,
        'realDepthMeters': widget.realDepthMeters,
        'modelBaseScale': widget.modelBaseScale,
      });
    } on PlatformException catch (error) {
      debugPrint('Failed to open native AR editor: $error');
      // We intentionally fail silently here and keep the existing Scene Viewer
      // path as the primary AR experience.
    }
  }

  /// Handles dimension messages from JavaScript bridge
  void _handleDimensionMessage(String message) {
    try {
      final Map<String, dynamic> payload = jsonDecode(message) as Map<String, dynamic>;
      final ArModelDimensions latest = ArModelDimensions.fromJson(payload);
      if (!mounted) return;
      setState(() => _dimensions = latest);
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to parse dimension bridge payload: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }


  /// JavaScript script that combines AR launch, dimension tracking, and scale correction
  String get _combinedScript => '''
(function() {
  const viewer = document.getElementById('$_viewerId');
  const channelName = '$_dimensionChannelName';
  if (!viewer) {
    console.warn('[AR Launcher] ModelViewer not found');
    return;
  }

  // Real-world dimensions from Flutter (in meters)
  const realWidthM = ${widget.realWidthMeters ?? 'null'};
  const realHeightM = ${widget.realHeightMeters ?? 'null'};
  const realDepthM = ${widget.realDepthMeters ?? 'null'};
  const baseScale = ${widget.modelBaseScale ?? 1.0};

  let lastPayload = '';
  let scaleFixed = false;

  // Function to post current dimensions to Flutter
  const postDimensions = () => {
    if (!viewer.getDimensions || typeof viewer.getDimensions !== 'function') {
      return;
    }
    const dims = viewer.getDimensions();
    if (!dims) {
      return;
    }
    const scale = viewer.scale || {x: 1, y: 1, z: 1};
    const serialized = JSON.stringify({
      widthMeters: Number(dims.x ?? 0),
      heightMeters: Number(dims.y ?? 0),
      depthMeters: Number(dims.z ?? 0),
      scaleX: Number(scale.x ?? scale[0] ?? 1),
      scaleY: Number(scale.y ?? scale[1] ?? 1),
      scaleZ: Number(scale.z ?? scale[2] ?? 1),
      arStatus: viewer.arStatus || 'not-presenting',
      timestamp: Date.now()
    });
    if (serialized === lastPayload) {
      return;
    }
    lastPayload = serialized;
    const bridge = window[channelName];
    if (bridge && typeof bridge.postMessage === 'function') {
      bridge.postMessage(serialized);
    }
  };

  // Function to automatically fix scale based on real-world dimensions
  const fixScale = () => {
    if (scaleFixed || !realWidthM || !realHeightM || !realDepthM) {
      return;
    }
    
    if (!viewer.getDimensions || typeof viewer.getDimensions !== 'function') {
      return;
    }
    
    const dims = viewer.getDimensions();
    if (!dims || dims.x <= 0 || dims.y <= 0 || dims.z <= 0) {
      return;
    }

    // Calculate required scale to match real-world size
    const widthScale = realWidthM / dims.x;
    const heightScale = realHeightM / dims.y;
    const depthScale = realDepthM / dims.z;
    
    // Use the maximum scale to ensure furniture appears at least as large as real size
    // This prevents the "looks small but is actually big" problem
    const requiredScale = Math.max(widthScale, heightScale, depthScale) * baseScale;
    
    // Only apply if scale is significantly off (more than 5% difference)
    const currentScale = viewer.scale?.x || 1.0;
    if (Math.abs(requiredScale - currentScale) / currentScale > 0.05) {
      console.log('[AR Launcher] Fixing scale:', {
        current: currentScale,
        required: requiredScale,
        realDims: {w: realWidthM, h: realHeightM, d: realDepthM},
        modelDims: {w: dims.x, h: dims.y, d: dims.z}
      });
      
      // Apply uniform scale to maintain proportions
      // Model-viewer accepts scale as a string in format "x y z" or a single number
      // For uniform scaling, we use the same value for all axes
      const scaleString = requiredScale.toString() + ' ' + requiredScale.toString() + ' ' + requiredScale.toString();
      viewer.setAttribute('scale', scaleString);
      // Also try setting as property (some model-viewer versions use this)
      if (viewer.scale !== undefined) {
        viewer.scale = scaleString;
      }
      scaleFixed = true;
      
      // Post updated dimensions after scale fix
      setTimeout(postDimensions, 100);
    }
  };

  // Function to attempt AR launch
  const launchAR = () => {
    // Check if AR is available and the button exists
    if (viewer.canActivateAR && viewer.arStatus === 'not-presenting') {
      // Find and click the AR button
      const arButton = viewer.shadowRoot?.querySelector('button[aria-label*="AR"], button[aria-label*="View in"], .ar-button, [slot="ar-button"]');
      if (arButton) {
        console.log('[AR Launcher] Clicking AR button');
        arButton.click();
        return true;
      }
      
      // Alternative: Try to activate AR programmatically
      if (viewer.activateAR) {
        console.log('[AR Launcher] Activating AR programmatically');
        viewer.activateAR();
        return true;
      }
    }
    return false;
  };

  // Initialize dimension tracking and scale fixing
  const kickOff = () => {
    postDimensions();
    
    // Try to fix scale when model is ready
    viewer.addEventListener('scene-graph-ready', () => {
      setTimeout(fixScale, 300);
      postDimensions();
    });
    
    viewer.addEventListener('model-visibility', () => {
      setTimeout(fixScale, 300);
      postDimensions();
    });
    
    viewer.addEventListener('load', () => {
      setTimeout(fixScale, 500);
      postDimensions();
      setTimeout(launchAR, 200);
    }, { once: true });
    
    viewer.addEventListener('progress', postDimensions);
    viewer.addEventListener('ar-status', () => {
      postDimensions();
      if (viewer.arStatus === 'not-presenting' && viewer.canActivateAR) {
        setTimeout(launchAR, 100);
      }
    });
    
    // MutationObserver for scale changes
    const observer = new MutationObserver(() => {
      postDimensions();
      if (!scaleFixed) {
        setTimeout(fixScale, 200);
      }
    });
    observer.observe(viewer, { attributes: true, attributeFilter: ['scale'] });
    
    // Poll for dimensions and scale fixing
    setInterval(() => {
      postDimensions();
      if (!scaleFixed) {
        fixScale();
      }
    }, 750);
    
    // Try AR launch
    if (viewer.loaded) {
      setTimeout(launchAR, 100);
    }
    
    // Fallback: Poll for AR button availability
    let attempts = 0;
    const maxAttempts = 20;
    const pollInterval = setInterval(() => {
      attempts++;
      if (launchAR() || attempts >= maxAttempts) {
        clearInterval(pollInterval);
      }
    }, 100);
  };

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    kickOff();
  } else {
    window.addEventListener('DOMContentLoaded', kickOff, { once: true });
  }
})();
''';

  @override
  Widget build(BuildContext context) {
    // On Android, show ModelViewer with AR enabled and combined script
    if (Platform.isAndroid && _resolved && _supportsArCore) {
      return CupertinoPageScaffold(
        backgroundColor: const Color(0xFFF9F4EF),
        navigationBar: CupertinoNavigationBar(
          middle: const Text('AR Preview'),
          trailing: _showGuidance
              ? null
              : CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _showGuidance = true),
                  child: const Icon(
                    CupertinoIcons.info_circle,
                    size: 22,
                  ),
                ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Responsive layout:
              // - Portrait: viewer on top, supporting panels below
              // - Landscape: viewer left, panels in a right-side rail
              //
              // This keeps the primary content (the 3D canvas / AR button)
              // dominant, which aligns with Apple HIG for immersive content.
              OrientationBuilder(
                builder: (BuildContext context, Orientation orientation) {
                  final bool isLandscape = orientation == Orientation.landscape;

                  // --- Shared: viewer -------------------------------------------------
                  final Widget viewer = ModelViewer(
                    backgroundColor: const Color(0xFFF9F4EF),
                    src: ModelPathHelper.normalize(widget.modelSrc),
                    alt: widget.altText,
                    ar: true,
                    arModes: const ['scene-viewer'],
                    arPlacement: ArPlacement.floor,
                    arScale: ArScale.auto,
                    cameraControls: true,
                    autoRotate: false,
                    disableZoom: false,
                    id: _viewerId,
                    relatedJs: _combinedScript,
                    javascriptChannels: <JavascriptChannel>{
                      JavascriptChannel(
                        _dimensionChannelName,
                        onMessageReceived: (dynamic message) {
                          final String messageStr = message is String ? message : (message?.toString() ?? '{}');
                          _handleDimensionMessage(messageStr);
                        },
                      ),
                    },
                  );

                  // --- Shared: panels ------------------------------------------------
                  final List<Widget> panels = <Widget>[
                    if (!_showGuidance) _PlacementTipsBanner(),
                    if (_dimensions != null ||
                        (widget.realWidthMeters != null &&
                            widget.realHeightMeters != null &&
                            widget.realDepthMeters != null))
                      _ArLauncherDimensionPanel(
                        dimensions: _dimensions,
                        realWidthMeters: widget.realWidthMeters,
                        realHeightMeters: widget.realHeightMeters,
                        realDepthMeters: widget.realDepthMeters,
                        onFixScale: () {
                          // Trigger scale fix via JavaScript.
                          // The JavaScript will automatically fix scale on next poll;
                          // we force a rebuild to refresh the readout immediately.
                          setState(() {});
                        },
                      ),
                  ];

                  // Portrait: stacked (simple + familiar).
                  if (!isLandscape) {
                    return Column(
                      children: [
                        Expanded(child: viewer),
                        ...panels,
                      ],
                    );
                  }

                  // Landscape: side rail (more comfortable on wide screens).
                  return Row(
                    children: [
                      Expanded(child: viewer),
                      SizedBox(
                        width: 380,
                        child: SafeArea(
                          left: false,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: panels,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              // Pre-AR guidance overlay
              if (_showGuidance)
                _ArGuidanceOverlay(
                  onDismiss: () => setState(() => _showGuidance = false),
                  realWidthMeters: widget.realWidthMeters,
                  realHeightMeters: widget.realHeightMeters,
                  realDepthMeters: widget.realDepthMeters,
                ),
            ],
          ),
        ),
      );
    }

    // Loading state
    if (!_resolved) {
      return CupertinoPageScaffold(
        backgroundColor: const Color(0xFFF9F4EF),
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Checking AR support...'),
        ),
        child: const SafeArea(
          child: Center(
            child: CupertinoActivityIndicator(),
          ),
        ),
      );
    }

    // Fallback: Show ModelViewer with AR button (user can manually click)
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF9F4EF),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('AR View'),
        trailing: _showGuidance
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _showGuidance = true),
                child: const Icon(
                  CupertinoIcons.info_circle,
                  size: 22,
                ),
              ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            // Same responsive layout as the "auto-launch" path above.
            OrientationBuilder(
              builder: (BuildContext context, Orientation orientation) {
                final bool isLandscape = orientation == Orientation.landscape;

                final Widget viewer = ModelViewer(
                  backgroundColor: const Color(0xFFF9F4EF),
                  src: ModelPathHelper.normalize(widget.modelSrc),
                  alt: widget.altText,
                  ar: _supportsArCore,
                  arModes: _supportsArCore ? const ['scene-viewer'] : const [],
                  arPlacement: ArPlacement.floor,
                  arScale: ArScale.auto,
                  cameraControls: true,
                  autoRotate: false,
                  disableZoom: false,
                  id: _viewerId,
                  relatedJs: _combinedScript,
                  javascriptChannels: <JavascriptChannel>{
                    JavascriptChannel(
                      _dimensionChannelName,
                      onMessageReceived: (dynamic message) {
                        final String messageStr = message is String ? message : (message?.toString() ?? '{}');
                        _handleDimensionMessage(messageStr);
                      },
                    ),
                  },
                );

                final List<Widget> panels = <Widget>[
                  if (!_showGuidance) _PlacementTipsBanner(),
                  if (_dimensions != null ||
                      (widget.realWidthMeters != null &&
                          widget.realHeightMeters != null &&
                          widget.realDepthMeters != null))
                    _ArLauncherDimensionPanel(
                      dimensions: _dimensions,
                      realWidthMeters: widget.realWidthMeters,
                      realHeightMeters: widget.realHeightMeters,
                      realDepthMeters: widget.realDepthMeters,
                      onFixScale: () => setState(() {}),
                    ),
                ];

                if (!isLandscape) {
                  return Column(
                    children: [
                      Expanded(child: viewer),
                      ...panels,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: viewer),
                    SizedBox(
                      width: 380,
                      child: SafeArea(
                        left: false,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: panels,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            // Pre-AR guidance overlay
            if (_showGuidance)
              _ArGuidanceOverlay(
                onDismiss: () => setState(() => _showGuidance = false),
                realWidthMeters: widget.realWidthMeters,
                realHeightMeters: widget.realHeightMeters,
                realDepthMeters: widget.realDepthMeters,
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact dimension panel for AR Launcher with scale fix button
/// Shows real-world size comparison and allows manual scale correction
class _ArLauncherDimensionPanel extends StatelessWidget {
  const _ArLauncherDimensionPanel({
    this.dimensions,
    this.realWidthMeters,
    this.realHeightMeters,
    this.realDepthMeters,
    required this.onFixScale,
  });

  final ArModelDimensions? dimensions;
  final double? realWidthMeters;
  final double? realHeightMeters;
  final double? realDepthMeters;
  final VoidCallback onFixScale;

  @override
  Widget build(BuildContext context) {
    // Calculate scale accuracy if we have both dimensions
    double? scaleAccuracy;
    bool needsScaleFix = false;
    
    if (dimensions != null && 
        realWidthMeters != null && 
        realHeightMeters != null && 
        realDepthMeters != null) {
      final widthPercent = (dimensions!.widthMeters / realWidthMeters!) * 100;
      final heightPercent = (dimensions!.heightMeters / realHeightMeters!) * 100;
      final depthPercent = (dimensions!.depthMeters / realDepthMeters!) * 100;
      
      final avgPercent = (widthPercent + heightPercent + depthPercent) / 3.0;
      scaleAccuracy = avgPercent;
      
      // Flag as needing fix if scale is off by more than 5%
      needsScaleFix = avgPercent < 95 || avgPercent > 105;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: needsScaleFix 
            ? const Color(0xFFFFF4E6) // Light orange background if scale is off
            : const Color(0xFFF5F5F7), // Light gray if scale is correct
        borderRadius: BorderRadius.circular(18),
        border: needsScaleFix
            ? Border.all(color: const Color(0xFFF59E0B), width: 2)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with status
          Row(
            children: [
              Icon(
                needsScaleFix 
                    ? CupertinoIcons.exclamationmark_triangle_fill
                    : CupertinoIcons.checkmark_circle_fill,
                size: 18,
                color: needsScaleFix 
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  needsScaleFix
                      ? 'Size may not match real-world dimensions'
                      : 'Displaying at real-world size',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: needsScaleFix 
                        ? const Color(0xFF92400E)
                        : const Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
          
          // Real-world dimensions display
          if (realWidthMeters != null && 
              realHeightMeters != null && 
              realDepthMeters != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Real-world size:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _SizeChip(
                          label: 'W',
                          meters: realWidthMeters!,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SizeChip(
                          label: 'H',
                          meters: realHeightMeters!,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SizeChip(
                          label: 'D',
                          meters: realDepthMeters!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          
          // Current display size (if available)
          if (dimensions != null && scaleAccuracy != null) ...[
            const SizedBox(height: 8),
            Text(
              'Currently displaying at ${scaleAccuracy!.toStringAsFixed(0)}% of real size',
              style: TextStyle(
                fontSize: 12,
                color: needsScaleFix 
                    ? const Color(0xFF92400E)
                    : const Color(0xFF4B5563),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          
          // Fix Scale button (only show if scale is off)
          if (needsScaleFix) ...[
            const SizedBox(height: 12),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 12),
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF0A84FF),
              onPressed: onFixScale,
              child: const Text(
                'Fix Scale to Real Size',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ],
          
          // Placement tip (always show)
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F4F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.lightbulb,
                  size: 16,
                  color: Color(0xFF0A84FF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tip: Move slowly to help ARCore detect surfaces. Place on flat, well-lit floors.',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF1F2933),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact placement tips banner shown during AR session
/// Provides quick reminders for optimal AR placement
class _PlacementTipsBanner extends StatelessWidget {
  const _PlacementTipsBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F4F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFB8E6F5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.info,
            size: 18,
            color: Color(0xFF0A84FF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Move device slowly to detect floor surfaces. Tap detected planes to place furniture.',
              style: TextStyle(
                fontSize: 13,
                color: const Color(0xFF1F2933),
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact size chip for displaying dimensions
class _SizeChip extends StatelessWidget {
  const _SizeChip({
    required this.label,
    required this.meters,
  });

  final String label;
  final double meters;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatMeters(meters),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMeters(double meters) {
    if (meters >= 1) {
      return '${meters.toStringAsFixed(2)}m';
    }
    return '${(meters * 100).toStringAsFixed(1)}cm';
  }
}

/// Pre-AR guidance overlay that provides instructions and tips
/// Following Apple's Human Interface Guidelines for clear, helpful guidance
class _ArGuidanceOverlay extends StatelessWidget {
  const _ArGuidanceOverlay({
    required this.onDismiss,
    this.realWidthMeters,
    this.realHeightMeters,
    this.realDepthMeters,
  });

  final VoidCallback onDismiss;
  final double? realWidthMeters;
  final double? realHeightMeters;
  final double? realDepthMeters;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.75),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.info_circle_fill,
                    color: CupertinoColors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'AR Placement Guide',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onDismiss,
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: CupertinoColors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Real-world dimensions (if available)
              if (realWidthMeters != null && 
                  realHeightMeters != null && 
                  realDepthMeters != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Real-World Size',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _GuidanceSizeChip(
                              label: 'Width',
                              meters: realWidthMeters!,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _GuidanceSizeChip(
                              label: 'Height',
                              meters: realHeightMeters!,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _GuidanceSizeChip(
                              label: 'Depth',
                              meters: realDepthMeters!,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 24),
              
              // Placement instructions
              _GuidanceSection(
                icon: CupertinoIcons.arrow_down_circle_fill,
                title: 'Step 1: Find a Flat Surface',
                description: 'Move your device slowly to scan the floor. ARCore will detect horizontal surfaces automatically. Look for a clear, well-lit area.',
              ),
              const SizedBox(height: 16),
              _GuidanceSection(
                icon: CupertinoIcons.hand_point_left_fill,
                title: 'Step 2: Tap to Place',
                description: 'When you see the AR button, tap it to launch AR. Then tap on a detected floor surface to place the furniture at that location.',
              ),
              const SizedBox(height: 16),
              _GuidanceSection(
                icon: CupertinoIcons.arrow_left_right,
                title: 'Step 3: Move Around',
                description: 'Walk around the placed furniture to see it from different angles. The object stays anchored to the floor surface.',
              ),
              
              const SizedBox(height: 24),
              
              // Tips section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.lightbulb_fill,
                          color: Color(0xFFFFD700),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Pro Tips',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TipItem(
                      '• Place furniture on stable, flat surfaces for best tracking',
                    ),
                    _TipItem(
                      '• Ensure good lighting - avoid very dark or overly bright areas',
                    ),
                    _TipItem(
                      '• Keep your device steady while ARCore detects surfaces',
                    ),
                    _TipItem(
                      '• Move at a comfortable distance (2-4 meters) for realistic scale perception',
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Shadow recommendation
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF3A3A3C),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.cube_fill,
                          color: Color(0xFF0A84FF),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Model Quality Note',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'For best visual results, 3D models should include:\n'
                      '• Baked shadows or shadow planes\n'
                      '• PBR materials (metallic-roughness)\n'
                      '• Textures at 2K resolution maximum',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFFAEAEB2),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Start AR button
              CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 16),
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFF0A84FF),
                onPressed: onDismiss,
                child: const Text(
                  'Got it, Launch AR',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatMeters(double meters) {
    if (meters >= 1) {
      return '${meters.toStringAsFixed(2)}m';
    }
    return '${(meters * 100).toStringAsFixed(1)}cm';
  }
}

/// Individual guidance section with icon, title, and description
class _GuidanceSection extends StatelessWidget {
  const _GuidanceSection({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFF0A84FF),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFAEAEB2),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tip item in the tips section
class _TipItem extends StatelessWidget {
  const _TipItem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFFAEAEB2),
          height: 1.4,
        ),
      ),
    );
  }
}

/// Size chip for guidance overlay
class _GuidanceSizeChip extends StatelessWidget {
  const _GuidanceSizeChip({
    required this.label,
    required this.meters,
  });

  final String label;
  final double meters;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFAEAEB2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatMeters(meters),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.white,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMeters(double meters) {
    if (meters >= 1) {
      return '${meters.toStringAsFixed(2)}m';
    }
    return '${(meters * 100).toStringAsFixed(1)}cm';
  }
}

