import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/ar_support_service.dart';

class ArViewScreen extends StatelessWidget {
  const ArViewScreen({
    super.key,
    required this.modelSrc,
    required this.altText,
    this.initialMode,
  });

  final String modelSrc;
  final String altText;
  final ArViewMode? initialMode;

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
  const _ArBody({required this.modelSrc, required this.altText, this.initialMode});

  final String modelSrc;
  final String altText;
  final ArViewMode? initialMode;

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

    return Column(
      children: <Widget>[
        // --- AR / 3D canvas --------------------------------------------------
        Expanded(
          child: ModelViewer(
            src: widget.modelSrc,
            alt: widget.altText,
            ar: arEnabledForMode,
            arModes: arModes,
            arPlacement: ArPlacement.floor,
            arScale: ArScale.auto,
            cameraControls: true,
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
                onMessageReceived: _handleDimensionMessage,
              ),
            },
          ),
        ),
        // --- Dimension readout -----------------------------------------------
        _DimensionReadout(dimensions: _dimensions),
        // --- Mode toggles ----------------------------------------------------
        _ModeToggleBar(
          activeMode: _mode,
          supportsArCore: supportsArCore,
          supportsWebXr: supportsWebXr,
          onModeChanged: (ArViewMode mode) => setState(() => _mode = mode),
        ),
        // --- Status / fallback hints ----------------------------------------
        _CapabilityBanner(
          capability: _capability,
          onRetry: _resolveArSupport,
        ),
      ],
    );
  }

  /// Consumes payloads from the JavaScript bridge and hydrates [_dimensions].
  void _handleDimensionMessage(JavaScriptMessage message) {
    try {
      final Map<String, dynamic> payload = jsonDecode(message.message) as Map<String, dynamic>;
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
    console.warn('[SmartSpace][AR] Missing viewer for dimension bridge.');
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
  const _DimensionReadout({required this.dimensions});

  final ArModelDimensions? dimensions;

  @override
  Widget build(BuildContext context) {
    if (dimensions == null) {
      return const SizedBox.shrink();
    }

    final ArModelDimensions dims = dimensions!;
    final List<_DimensionEntry> entries = <_DimensionEntry>[
      _DimensionEntry(label: 'Width', meters: dims.widthMeters),
      _DimensionEntry(label: 'Height', meters: dims.heightMeters),
      _DimensionEntry(label: 'Depth', meters: dims.depthMeters),
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
                  '${_formatMeters(dims.footprintSquareMeters)}²',
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
                        metricValue: _formatMeters(entry.meters),
                        imperialValue: _formatImperial(entry.meters),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 10),
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

  static String _formatMeters(double meters) {
    if (meters >= 1) {
      return '${meters.toStringAsFixed(2)}m';
    }
    return '${(meters * 100).toStringAsFixed(1)}cm';
  }

  static String _formatImperial(double meters) {
    final double inches = meters * 39.3701;
    final int feet = (inches / 12).floor();
    final double remainingInches = inches - (feet * 12);
    if (feet <= 0) {
      return '${remainingInches.toStringAsFixed(1)}in';
    }
    return '${feet}ft ${remainingInches.toStringAsFixed(0)}in';
  }
}

class _DimensionEntry {
  const _DimensionEntry({required this.label, required this.meters});

  final String label;
  final double meters;
}

class _DimensionChip extends StatelessWidget {
  const _DimensionChip({
    required this.label,
    required this.metricValue,
    required this.imperialValue,
  });

  final String label;
  final String metricValue;
  final String imperialValue;

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
                metricValue,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              Text(
                imperialValue,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF4B5563),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



