import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> saveReportFile({
  required String filename,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final directory = await getDownloadsDirectory() ?? await getTemporaryDirectory();
  final file = File('${directory.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
