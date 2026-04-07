/// Web build: ModelViewer loads from network/URLs; no local disk cache.
Future<String> resolveModelSourceForViewer(String normalizedSrc) async => normalizedSrc;
