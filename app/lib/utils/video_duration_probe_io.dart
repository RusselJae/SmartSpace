import 'dart:io';

import 'package:video_player/video_player.dart';

Future<Duration?> probeVideoDuration(String path) async {
  VideoPlayerController? controller;
  try {
    controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    return controller.value.duration;
  } catch (_) {
    return null;
  } finally {
    await controller?.dispose();
  }
}
