/// Web build: ModelViewer loads from network/URLs; no local disk cache.
Future<String> resolveModelSourceForViewer(String normalizedSrc) async => normalizedSrc;

/// No-op on web — nothing to warm.
Future<void> prefetchModelSources(Iterable<String> normalizedSrcs) async {}
