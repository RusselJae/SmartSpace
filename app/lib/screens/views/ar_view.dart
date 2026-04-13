import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../services/ar_support_service.dart';
import '../../utils/model_path_helper.dart';
import '../../utils/dimension_format.dart';
import '../../widgets/cached_model_src_loader.dart';

class ArViewScreen extends StatelessWidget {
  const ArViewScreen({
    super.key,
    required this.modelSrc,
    required this.altText,
    this.initialMode,
    this.realWidthMeters,
    this.realHeightMeters,
    this.realDepthMeters,
  });

  final String modelSrc;
  final String altText;
  final ArViewMode? initialMode;
  final double? realWidthMeters;
  final double? realHeightMeters;
  final double? realDepthMeters;

  static const String route = '/ar-view';

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('AR Preview'),
      ),
      child: SafeArea(
        child: _ArBody(
          modelSrc: modelSrc,
          altText: altText,
          initialMode: initialMode,
          realWidthMeters: realWidthMeters,
          realHeightMeters: realHeightMeters,
          realDepthMeters: realDepthMeters,
        ),
      ),
    );
  }
}

enum ArViewMode { arcore, webxr }

/// ###########################################################################
/// ## ArModelDimensions                                                      ##
/// ###########################################################################
/// This tiny data object keeps the current bounding-box that the WebXR
/// `<model-viewer>` surface reports after applying any runtime scaling.
/// Everything is normalized to meters so we can convert to cm/ft for the UI.
class ArModelDimensions {
  const ArModelDimensions({
    required this.widthMeters,
    required this.heightMeters,
    required this.depthMeters,
    required this.scaleX,
    required this.scaleY,
    required this.scaleZ,
    required this.timestampMs,
    required this.arStatus,
  });

  factory ArModelDimensions.fromJson(Map<String, dynamic> json) {
    // Defensive parsing ensures bad JS payloads never crash the Flutter side.
    double safeDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return ArModelDimensions(
      widthMeters: safeDouble(json['widthMeters']),
      heightMeters: safeDouble(json['heightMeters']),
      depthMeters: safeDouble(json['depthMeters']),
      scaleX: safeDouble(json['scaleX']),
      scaleY: safeDouble(json['scaleY']),
      scaleZ: safeDouble(json['scaleZ']),
      timestampMs: (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      arStatus: json['arStatus']?.toString() ?? 'unknown',
    );
  }

  final double widthMeters;
  final double heightMeters;
  final double depthMeters;
  final double scaleX;
  final double scaleY;
  final double scaleZ;
  final int timestampMs;
  final String arStatus;

  /// Simple derived helper so we can quickly mention the occupied floor area.
  double get footprintSquareMeters => widthMeters * depthMeters;
}

class _ArBody extends StatefulWidget {
  const _ArBody({
    required this.modelSrc,
    required this.altText,
    this.initialMode,
    this.realWidthMeters,
    this.realHeightMeters,
    this.realDepthMeters,
  });

  final String modelSrc;
  final String altText;
  final ArViewMode? initialMode;
  final double? realWidthMeters;
  final double? realHeightMeters;
  final double? realDepthMeters;

  @override
  State<_ArBody> createState() => _ArBodyState();
}

class _ArBodyState extends State<_ArBody> {
  final ArSupportService _supportService = ArSupportService.instance;

  static const String _dimensionChannelName = 'DimensionBridge';

  bool _resolved = false;
  late ArCapabilityResult _capability;
  ArViewMode _mode = ArViewMode.arcore;
  late final String _viewerId;
  ArModelDimensions? _dimensions;

  @override
  void initState() {
    super.initState();
    _viewerId = 'ar-viewer-${widget.modelSrc.hashCode & 0xFFFFFFF}';
    _resolveArSupport();
  }

  Future<void> _resolveArSupport() async {
    // We resolve capability on-demand so the user can retry if Google Play
    // services get installed while the screen is open.
    final ArCapabilityResult capability = await _supportService.resolveCapability();
    final ArViewMode? preferred = widget.initialMode;
    ArViewMode resolvedMode;
    if (preferred == ArViewMode.arcore && capability.supportsSceneViewer) {
      resolvedMode = ArViewMode.arcore;
    } else if (preferred == ArViewMode.webxr && capability.supportsWebXr) {
      resolvedMode = ArViewMode.webxr;
    } else if (capability.supportsSceneViewer) {
      resolvedMode = ArViewMode.arcore;
    } else if (capability.supportsWebXr) {
      resolvedMode = ArViewMode.webxr;
    } else {
      resolvedMode = ArViewMode.arcore;
    }
    if (!mounted) return;
    setState(() {
      _capability = capability;
      _mode = resolvedMode;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return const Center(child: CupertinoActivityIndicator());
    }

    // Layout keeps the viewer flexible while reserving room for status hints.
    //
    // NOTE ABOUT LANDSCAPE (Apple HIG):
    // - In landscape, people expect "content-first" layouts where the primary
    //   canvas stays large and supporting controls move to a side rail.
    // - This also avoids the "short + cramped" stacked-column feel on phones.
    final bool supportsArCore = _capability.enableAr && _capability.supportsSceneViewer;
    final bool supportsWebXr = _capability.enableAr && _capability.supportsWebXr;

    bool arEnabledForMode = false;
    List<String> arModes = const <String>[];
    switch (_mode) {
      case ArViewMode.arcore:
        arEnabledForMode = supportsArCore;
        arModes = supportsArCore ? const <String>['scene-viewer'] : const <String>[];
        break;
      case ArViewMode.webxr:
        arEnabledForMode = supportsWebXr;
        arModes = supportsWebXr ? const <String>['webxr'] : const <String>[];
        break;
    }

    // --- Shared: the 3D / AR canvas -----------------------------------------
    final Widget viewer = CachedModelSrcLoader(
      sourceUrl: ModelPathHelper.normalize(widget.modelSrc),
      builder: (context, resolvedSrc) => ModelViewer(
        src: resolvedSrc,
        alt: widget.altText,
        ar: arEnabledForMode,
        arModes: arModes,
        arPlacement: ArPlacement.floor,
        arScale: ArScale.auto,
        cameraControls: true,
        environmentImage: 'neutral',
        exposure: 1.35,
        shadowIntensity: 0.18,
        autoRotate: false,
        disableZoom: false,
        touchAction: TouchAction.none,
        iosSrc: null,
        backgroundColor: const Color(0xFFFFFFFF),
        id: _viewerId,
        // Inject custom JS so we can query `<model-viewer>` for its live
        // bounding-box and current scale factors.
        relatedJs: _dimensionProbeScript,
        javascriptChannels: <JavascriptChannel>{
          JavascriptChannel(
            _dimensionChannelName,
            onMessageReceived: (dynamic message) {
              // Extract message string from the callback parameter
              final String messageStr = message is String ? message : (message?.toString() ?? '{}');
              _handleDimensionMessage(messageStr);
            },
          ),
        },
      ),
    );

    // --- Shared: supporting UI panels ---------------------------------------
    final List<Widget> panels = <Widget>[
      _DimensionReadout(
        dimensions: _dimensions,
        realWidthMeters: widget.realWidthMeters,
        realHeightMeters: widget.realHeightMeters,
        realDepthMeters: widget.realDepthMeters,
      ),
      _ModeToggleBar(
        activeMode: _mode,
        supportsArCore: supportsArCore,
        supportsWebXr: supportsWebXr,
        onModeChanged: (ArViewMode mode) => setState(() => _mode = mode),
      ),
      _CapabilityBanner(
        capability: _capability,
        onRetry: _resolveArSupport,
      ),
    ];

    // --- Responsive composition ---------------------------------------------
    return OrientationBuilder(
      builder: (BuildContext context, Orientation orientation) {
        final bool isLandscape = orientation == Orientation.landscape;

        // Portrait: classic stacked layout (works well on narrow phones).
        if (!isLandscape) {
          return Column(
            children: <Widget>[
              Expanded(child: viewer),
              ...panels,
            ],
          );
        }

        // Landscape: keep the viewer big, move controls into a side rail.
        //
        // This matches Apple HIG expectations for wide layouts (primary content
        // on the left, controls on the right) and prevents the bottom stack from
        // feeling cramped.
        return Row(
          children: <Widget>[
            Expanded(child: viewer),
            SizedBox(
              width: 360,
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
    );
  }

  /// Consumes payloads from the JavaScript bridge and hydrates [_dimensions].
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

  /// Generates the JavaScript snippet that probes `<model-viewer>` metrics.
  String get _dimensionProbeScript => '''
(function () {
  const viewer = document.getElementById('$_viewerId');
  const channelName = '$_dimensionChannelName';
  if (!viewer) {
    console.warn('[Wood Home Furniture Trading][AR] Missing viewer for dimension bridge.');
    return;
  }

  let lastPayload = '';

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

  const kickOff = () => {
    postDimensions();
    viewer.addEventListener('scene-graph-ready', postDimensions);
    viewer.addEventListener('model-visibility', postDimensions);
    viewer.addEventListener('progress', postDimensions);
    viewer.addEventListener('ar-status', postDimensions);
    viewer.addEventListener('load', postDimensions);
    // MutationObserver lets us react when the Flutter side updates `scale`.
    const observer = new MutationObserver(postDimensions);
    observer.observe(viewer, { attributes: true, attributeFilter: ['scale'] });
    // Gentle polling covers pinch-zoom inside the embedded viewer.
    setInterval(postDimensions, 750);
  };

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    kickOff();
  } else {
    window.addEventListener('DOMContentLoaded', kickOff, { once: true });
  }
})();
''';
}

class _ModeToggleBar extends StatelessWidget {
  const _ModeToggleBar({
    required this.activeMode,
    required this.supportsArCore,
    required this.supportsWebXr,
    required this.onModeChanged,
  });

  final ArViewMode activeMode;
  final bool supportsArCore;
  final bool supportsWebXr;
  final ValueChanged<ArViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    // Apple HIG prefers clearly labeled, high-contrast primary actions, so we use
    // two chunky buttons with enough spacing for both thumb reach and mouse taps.
    // The copy makes it obvious which mode anchors to ARCore Scene Viewer vs WebXR.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 16),
              borderRadius: BorderRadius.circular(14),
              color: activeMode == ArViewMode.arcore ? const Color(0xFF0A84FF) : const Color(0xFFE5E7EB),
              onPressed: supportsArCore ? () => onModeChanged(ArViewMode.arcore) : null,
              child: Text(
                'ARCore',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: supportsArCore
                      ? (activeMode == ArViewMode.arcore ? const Color(0xFFFFFFFF) : const Color(0xFF111827))
                      : const Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 16),
              borderRadius: BorderRadius.circular(14),
              color: activeMode == ArViewMode.webxr ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
              onPressed: supportsWebXr ? () => onModeChanged(ArViewMode.webxr) : null,
              child: Text(
                'WebXR',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: supportsWebXr
                      ? (activeMode == ArViewMode.webxr ? const Color(0xFFFFFFFF) : const Color(0xFF111827))
                      : const Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityBanner extends StatelessWidget {
  const _CapabilityBanner({
    required this.capability,
    required this.onRetry,
  });

  final ArCapabilityResult capability;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Multi-line padding keeps the section airy on phones + tablets.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: capability.usesWebFallback ? const Color(0xFFF4F6F8) : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    capability.headline,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2933),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    capability.detail,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 14),
            borderRadius: BorderRadius.circular(12),
            color: const Color(0xFF111827),
            onPressed: onRetry,
            child: const Text(
              'Re-check AR support',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact summary card that mirrors Apple HIG spacing + typography guidance.
class _DimensionReadout extends StatelessWidget {
  const _DimensionReadout({
    required this.dimensions,
    this.realWidthMeters,
    this.realHeightMeters,
    this.realDepthMeters,
  });

  final ArModelDimensions? dimensions;
  final double? realWidthMeters;
  final double? realHeightMeters;
  final double? realDepthMeters;

  @override
  Widget build(BuildContext context) {
    if (dimensions == null) {
      return const SizedBox.shrink();
    }

    final ArModelDimensions dims = dimensions!;
    
    // Calculate percentages if real dimensions are available
    final double? widthPercent = realWidthMeters != null && realWidthMeters! > 0
        ? (dims.widthMeters / realWidthMeters!) * 100
        : null;
    final double? heightPercent = realHeightMeters != null && realHeightMeters! > 0
        ? (dims.heightMeters / realHeightMeters!) * 100
        : null;
    final double? depthPercent = realDepthMeters != null && realDepthMeters! > 0
        ? (dims.depthMeters / realDepthMeters!) * 100
        : null;
    
    final List<_DimensionEntry> entries = <_DimensionEntry>[
      _DimensionEntry(
        label: 'Width',
        meters: dims.widthMeters,
        realMeters: realWidthMeters,
        percent: widthPercent,
      ),
      _DimensionEntry(
        label: 'Height',
        meters: dims.heightMeters,
        realMeters: realHeightMeters,
        percent: heightPercent,
      ),
      _DimensionEntry(
        label: 'Depth',
        meters: dims.depthMeters,
        realMeters: realDepthMeters,
        percent: depthPercent,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInOutCubicEmphasized,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(CupertinoIcons.rectangle, size: 18, color: Color(0xFF111827)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Live footprint (${dims.arStatus})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                Text(
                  DimensionFormat.formatSquareMetersAsSquareInches(
                    dims.footprintSquareMeters,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: entries
                  .map(
                    (entry) => Expanded(
                      child: _DimensionChip(
                        label: entry.label,
                        sizeLabel: DimensionFormat.formatMetersAsInches(entry.meters),
                        realMeters: entry.realMeters,
                        percent: entry.percent,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 10),
            // Show real size comparison if available
            if (realWidthMeters != null || realHeightMeters != null || realDepthMeters != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _getSizeStatusColor(widthPercent, heightPercent, depthPercent),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getSizeStatusIcon(widthPercent, heightPercent, depthPercent),
                      size: 14,
                      color: CupertinoColors.white,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _getSizeStatusText(widthPercent, heightPercent, depthPercent),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Scale XYZ: ${dims.scaleX.toStringAsFixed(2)}× / '
                '${dims.scaleY.toStringAsFixed(2)}× / ${dims.scaleZ.toStringAsFixed(2)}×',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getSizeStatusColor(double? w, double? h, double? d) {
    // Average percentage if multiple dimensions available
    final List<double> percents = [w, h, d].whereType<double>().toList();
    if (percents.isEmpty) return const Color(0xFF6B7280);
    final double avg = percents.reduce((a, b) => a + b) / percents.length;
    
    if (avg >= 95 && avg <= 105) {
      return const Color(0xFF10B981); // Green for ~100%
    } else if (avg >= 80 && avg < 95) {
      return const Color(0xFFF59E0B); // Orange for smaller
    } else if (avg > 105 && avg <= 120) {
      return const Color(0xFFF59E0B); // Orange for larger
    } else {
      return const Color(0xFFEF4444); // Red for way off
    }
  }

  IconData _getSizeStatusIcon(double? w, double? h, double? d) {
    final List<double> percents = [w, h, d].whereType<double>().toList();
    if (percents.isEmpty) return CupertinoIcons.info;
    final double avg = percents.reduce((a, b) => a + b) / percents.length;
    
    if (avg >= 95 && avg <= 105) {
      return CupertinoIcons.check_mark_circled_solid;
    } else if (avg < 95) {
      return CupertinoIcons.arrow_down_circle;
    } else {
      return CupertinoIcons.arrow_up_circle;
    }
  }

  String _getSizeStatusText(double? w, double? h, double? d) {
    final List<double> percents = [w, h, d].whereType<double>().toList();
    if (percents.isEmpty) return 'Real size data unavailable';
    
    final double avg = percents.reduce((a, b) => a + b) / percents.length;
    
    if (avg >= 95 && avg <= 105) {
      return 'At real size (${avg.toStringAsFixed(0)}%)';
    } else if (avg < 95) {
      return '${avg.toStringAsFixed(0)}% of real size (smaller)';
    } else {
      return '${avg.toStringAsFixed(0)}% of real size (larger)';
    }
  }
}

class _DimensionEntry {
  const _DimensionEntry({
    required this.label,
    required this.meters,
    this.realMeters,
    this.percent,
  });

  final String label;
  final double meters;
  final double? realMeters;
  final double? percent;
}

class _DimensionChip extends StatelessWidget {
  const _DimensionChip({
    required this.label,
    required this.sizeLabel,
    this.realMeters,
    this.percent,
  });

  final String label;
  final String sizeLabel;
  final double? realMeters;
  final double? percent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sizeLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              if (percent != null)
                Text(
                  '${percent!.toStringAsFixed(0)}% of real',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: percent! >= 95 && percent! <= 105
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}



