import '../models/product.dart';

enum SuggestionFilter {
  all,
  recentlyViewed,
  liked,
  category,
  trending,
}

class ProductSuggestion {
  const ProductSuggestion({
    required this.product,
    required this.reason,
    required this.filter,
    this.badge,
  });

  final Product product;
  final String reason;
  final SuggestionFilter filter;
  final String? badge;
}

class ProductSuggestionService {
  const ProductSuggestionService();

  List<ProductSuggestion> buildSuggestions({
    required List<Product> allProducts,
    required List<String> recentIds,
    required List<Product> wishlistProducts,
    required List<String> purchasedIds,
    required List<Product> trendingProducts,
  }) {
    final byId = {for (final p in allProducts) p.id: p};
    final seen = <String>{};
    final results = <ProductSuggestion>[];

    void add(Product? product, String reason, SuggestionFilter filter, {String? badge}) {
      if (product == null || seen.contains(product.id) || product.isArchived) return;
      seen.add(product.id);
      results.add(ProductSuggestion(
        product: product,
        reason: reason,
        filter: filter,
        badge: badge,
      ));
    }

    for (final id in recentIds) {
      final product = byId[id];
      if (product == null) continue;
      final category = product.category.isNotEmpty ? product.category.toLowerCase() : 'furniture';
      add(product, 'Because you viewed $category', SuggestionFilter.recentlyViewed);
    }

    final likedCategories = wishlistProducts.map((p) => p.category).where((c) => c.isNotEmpty).toSet();
    for (final liked in wishlistProducts) {
      add(liked, 'From your liked items', SuggestionFilter.liked, badge: 'Top Pick');
    }
    for (final category in likedCategories) {
      for (final product in allProducts) {
        if (product.category == category && !wishlistProducts.any((w) => w.id == product.id)) {
          add(product, 'Similar to liked', SuggestionFilter.liked);
        }
      }
    }

    final categoryCounts = <String, int>{};
    for (final id in [...recentIds, ...purchasedIds]) {
      final product = byId[id];
      if (product == null || product.category.isEmpty) continue;
      categoryCounts[product.category] = (categoryCounts[product.category] ?? 0) + 1;
    }
    if (categoryCounts.isNotEmpty) {
      final topCategory = categoryCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      for (final product in allProducts) {
        if (product.category == topCategory) {
          add(product, 'Popular in $topCategory', SuggestionFilter.category);
        }
      }
    }

    for (final product in trendingProducts) {
      add(
        product,
        'Trending now',
        SuggestionFilter.trending,
        badge: product.isNewArrival ? 'New' : null,
      );
    }

    for (final product in allProducts) {
      if (results.length >= 24) break;
      add(product, 'Recommended for you', SuggestionFilter.trending);
    }

    return results;
  }

  List<ProductSuggestion> filterSuggestions(
    List<ProductSuggestion> suggestions,
    SuggestionFilter filter,
  ) {
    if (filter == SuggestionFilter.all) return suggestions;
    return suggestions.where((s) => s.filter == filter).toList();
  }

  String? topCategoryLabel({
    required List<String> recentIds,
    required List<String> purchasedIds,
    required Map<String, Product> byId,
  }) {
    final categoryCounts = <String, int>{};
    for (final id in [...recentIds, ...purchasedIds]) {
      final product = byId[id];
      if (product == null || product.category.isEmpty) continue;
      categoryCounts[product.category] = (categoryCounts[product.category] ?? 0) + 1;
    }
    if (categoryCounts.isEmpty) return null;
    return categoryCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}
