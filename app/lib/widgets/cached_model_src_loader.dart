import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../services/model_file_cache.dart';

/// Resolves a model URL through [ModelFileCacheService], then builds [ModelViewer]
/// (or any widget) with the cached `file://` path on IO platforms.
class CachedModelSrcLoader extends StatefulWidget {
  const CachedModelSrcLoader({
    super.key,
    required this.sourceUrl,
    required this.builder,
    this.placeholder,
  });

  /// Pass [ModelPathHelper.normalize] output (or any final viewer `src`).
  final String sourceUrl;
  final Widget Function(BuildContext context, String resolvedSrc) builder;
  final Widget? placeholder;

  @override
  State<CachedModelSrcLoader> createState() => _CachedModelSrcLoaderState();
}

class _CachedModelSrcLoaderState extends State<CachedModelSrcLoader> {
  String? _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CachedModelSrcLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceUrl != widget.sourceUrl) {
      _resolved = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final raw = widget.sourceUrl.trim();
    if (raw.isEmpty) {
      if (mounted) setState(() => _resolved = raw);
      return;
    }

    try {
      final out = await ModelFileCacheService.resolveForViewer(raw);
      if (mounted) setState(() => _resolved = out);
    } catch (e, st) {
      if (mounted) setState(() => _resolved = raw);
      if (kDebugMode) {
        debugPrint('CachedModelSrcLoader: cache resolve failed, using network URL: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _resolved;
    if (r != null) {
      return widget.builder(context, r);
    }
    return widget.placeholder ??
        const Center(
          child: CupertinoActivityIndicator(radius: 14),
        );
  }
}
