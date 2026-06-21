export 'video_duration_probe_stub.dart'
    if (dart.library.io) 'video_duration_probe_io.dart'
    if (dart.library.html) 'video_duration_probe_web.dart';
