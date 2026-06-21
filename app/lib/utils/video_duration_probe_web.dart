import 'package:video_player/video_player.dart';

Future<Duration?> probeVideoDuration(String path) async {
  VideoPlayerController? controller;
  try {
    final uri = Uri.parse(path);
    controller = VideoPlayerController.networkUrl(uri);
    await controller.initialize();
    return controller.value.duration;
  } catch (_) {
    return null;
  } finally {
    await controller?.dispose();
  }
}
