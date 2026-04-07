import 'dart:typed_data';

import 'report_file_saver_io.dart' if (dart.library.html) 'report_file_saver_web.dart' as saver;

Future<String> saveReportFile({
  required String filename,
  required Uint8List bytes,
  required String mimeType,
}) {
  return saver.saveReportFile(
    filename: filename,
    bytes: bytes,
    mimeType: mimeType,
  );
}
