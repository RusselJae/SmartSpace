import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../utils/model_path_helper.dart';
import '../../widgets/cached_model_src_loader.dart';

/// =============================================================
/// SceneViewScreen
///
/// Simple full-screen 3D model viewer with camera controls.
/// Provides an immersive scene view experience without AR options.
/// Following Apple's Human Interface Guidelines for a sleek, modern experience.
/// =============================================================
class SceneViewScreen extends StatelessWidget {
  const SceneViewScreen({
    super.key,
    required this.modelSrc,
    required this.altText,
  });

  final String modelSrc;
  final String altText;

  static const String route = '/scene-view';

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF9F4EF),
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          'Scene View',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      child: SafeArea(
        child: CachedModelSrcLoader(
          sourceUrl: ModelPathHelper.normalize(modelSrc),
          builder: (context, resolvedSrc) => ModelViewer(
            backgroundColor: const Color(0xFFF9F4EF),
            src: resolvedSrc,
            alt: altText,
            ar: false,
            environmentImage: 'neutral',
            exposure: 1.35,
            shadowIntensity: 0.18,
            autoRotate: false,
            cameraControls: true,
            disableZoom: false,
            interactionPrompt: InteractionPrompt.whenFocused,
          ),
        ),
      ),
    );
  }
}

