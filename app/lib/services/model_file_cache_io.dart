import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// In-flight downloads keyed by canonical URL (dedupes parallel callers).
final Map<String, Future<File>> _inFlight = {};

/// In-flight bundled-asset copies (avoids N parallel 50MB writes for N cards).
final Map<String, Future<String>> _assetMaterializeInFlight = {};

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

bool _isBundledAsset(String src) => src.startsWith('assets/');

String _cacheFileNameForAsset(String assetPath) {
  final digest = sha256.convert(utf8.encode(assetPath));
  final lower = assetPath.toLowerCase();
  final ext = lower.contains('.gltf') ? '.gltf' : '.glb';
  return 'bundled_${digest.toString()}$ext';
}

/// Copies a Flutter bundled GLB/GLTF to app storage so WebView / native loaders
/// can open large offline models reliably.
Future<String> _materializeBundledAsset(String assetPath) async {
  try {
    return await _assetMaterializeInFlight.putIfAbsent(
      assetPath,
      () => _materializeBundledAssetOnce(assetPath),
    );
  } finally {
    _assetMaterializeInFlight.remove(assetPath);
  }
}

Future<String> _materializeBundledAssetOnce(String assetPath) async {
  final dir = await _cacheDir();
  final target = File(p.join(dir.path, _cacheFileNameForAsset(assetPath)));
  if (await target.exists()) {
    final len = await target.length();
    if (len > 0) {
      return Uri.file(target.absolute.path).toString();
    }
    await target.delete();
  }

  final data = await rootBundle.load(assetPath);
  final part = File('${target.path}.part');
  if (await part.exists()) await part.delete();
  await part.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  if (await target.exists()) await target.delete();
  await part.rename(target.path);
  return Uri.file(target.absolute.path).toString();
}

/// Downloads [url] when missing, returns a `file://` URI for ModelViewer.
Future<String> resolveModelSourceForViewer(String normalizedSrc) async {
  final trimmed = normalizedSrc.trim();
  if (trimmed.isEmpty) return trimmed;
  if (_isBundledAsset(trimmed)) {
    try {
      return await _materializeBundledAsset(trimmed);
    } catch (_) {
      return trimmed;
    }
  }
  if (trimmed.startsWith('file://')) {
    return trimmed;
  }
  if (!_isRemote(trimmed)) {
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

/// Pre-downloads remote model URLs **sequentially** (never parallel — avoids OOM).
/// Bundled assets are skipped; they already ship inside the APK.
Future<void> prefetchModelSources(Iterable<String> normalizedSrcs) async {
  final unique = <String>{};
  for (final s in normalizedSrcs) {
    final t = s.trim();
    if (t.isEmpty) continue;
    if (_isBundledAsset(t)) continue;
    if (_isRemote(t)) unique.add(t);
  }
  if (unique.isEmpty) return;
  for (final src in unique) {
    try {
      await resolveModelSourceForViewer(src);
    } catch (_) {
      // Continue with remaining URLs.
    }
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
