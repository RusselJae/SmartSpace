import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// In-flight downloads keyed by canonical URL (dedupes parallel callers).
final Map<String, Future<File>> _inFlight = {};

/// Stable cache file name from remote URL (handles long paths & query strings).
String _cacheFileNameForUrl(String url) {
  final digest = sha256.convert(utf8.encode(url));
  final lower = url.toLowerCase();
  final ext = lower.contains('.gltf') ? '.gltf' : '.glb';
  return '${digest.toString()}$ext';
}

Future<Directory> _cacheDir() async {
  final root = await getApplicationSupportDirectory();
  final dir = Directory(p.join(root.path, 'model_glb_cache'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

bool _isRemote(String src) =>
    src.startsWith('http://') || src.startsWith('https://');

/// Downloads [url] when missing, returns a `file://` URI for ModelViewer.
Future<String> resolveModelSourceForViewer(String normalizedSrc) async {
  final trimmed = normalizedSrc.trim();
  if (trimmed.isEmpty) return trimmed;
  if (!_isRemote(trimmed)) {
    // Bundled assets or relative paths — ModelViewer handles these.
    return trimmed;
  }

  final dir = await _cacheDir();
  final name = _cacheFileNameForUrl(trimmed);
  final target = File(p.join(dir.path, name));

  if (await target.exists()) {
    final len = await target.length();
    if (len > 0) {
      return Uri.file(target.absolute.path).toString();
    }
    await target.delete();
  }

  try {
    final file = await _inFlight.putIfAbsent(trimmed, () => _download(trimmed, target));
    return Uri.file(file.absolute.path).toString();
  } catch (_) {
    // WebView can still try the network URL if cache/download fails.
    return trimmed;
  } finally {
    _inFlight.remove(trimmed);
  }
}

Future<File> _download(String url, File target) async {
  final uri = Uri.parse(url);
  final response = await http.get(uri).timeout(const Duration(minutes: 5));
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode}', uri: uri);
  }
  final bytes = response.bodyBytes;
  if (bytes.isEmpty) {
    throw HttpException('Empty response body', uri: uri);
  }

  final part = File('${target.path}.part');
  if (await part.exists()) await part.delete();
  await part.writeAsBytes(bytes, flush: true);

  if (await target.exists()) await target.delete();
  await part.rename(target.path);
  return target;
}
