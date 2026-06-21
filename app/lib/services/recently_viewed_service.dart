import 'package:shared_preferences/shared_preferences.dart';

/// Persists recently viewed product IDs for signed-in personalization.
class RecentlyViewedService {
  RecentlyViewedService._();

  static final RecentlyViewedService instance = RecentlyViewedService._();

  static const String _key = 'smartspace.recently_viewed_product_ids';
  static const int _maxItems = 20;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> recordView(String productId) async {
    if (productId.isEmpty) return;
    final prefs = await _ensurePrefs();
    final current = prefs.getStringList(_key) ?? <String>[];
    final updated = [productId, ...current.where((id) => id != productId)];
    if (updated.length > _maxItems) {
      updated.removeRange(_maxItems, updated.length);
    }
    await prefs.setStringList(_key, updated);
  }

  Future<List<String>> getRecentIds() async {
    final prefs = await _ensurePrefs();
    return prefs.getStringList(_key) ?? const [];
  }
}
