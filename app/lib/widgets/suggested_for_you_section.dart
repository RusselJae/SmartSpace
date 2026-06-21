import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/product.dart';
import '../services/product_suggestion_service.dart';
import '../utils/model_path_helper.dart';

class SuggestedForYouSection extends StatefulWidget {
  const SuggestedForYouSection({
    super.key,
    required this.suggestions,
    required this.topCategory,
    required this.onProductTap,
    required this.onSeeAll,
  });

  final List<ProductSuggestion> suggestions;
  final String? topCategory;
  final ValueChanged<Product> onProductTap;
  final VoidCallback onSeeAll;

  @override
  State<SuggestedForYouSection> createState() => _SuggestedForYouSectionState();
}

class _SuggestedForYouSectionState extends State<SuggestedForYouSection> {
  SuggestionFilter _activeFilter = SuggestionFilter.all;

  static const Color _walnut = Color(0xFF8D6E63);
  static const Color _headerBg = Color(0xFFF9F4EF);

  List<ProductSuggestion> get _visible {
    const service = ProductSuggestionService();
    return service.filterSuggestions(widget.suggestions, _activeFilter);
  }

  String _formatPrice(double price) {
    final text = price.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) return const SizedBox.shrink();

    final chips = <_ChipData>[
      _ChipData('Recently viewed', SuggestionFilter.recentlyViewed, CupertinoIcons.eye, const Color(0xFF1976D2)),
      _ChipData('Liked items', SuggestionFilter.liked, CupertinoIcons.heart_fill, CupertinoColors.systemRed),
      if (widget.topCategory != null)
        _ChipData(widget.topCategory!, SuggestionFilter.category, CupertinoIcons.square_grid_2x2, const Color(0xFF388E3C)),
      _ChipData('Trending', SuggestionFilter.trending, CupertinoIcons.arrow_up_right, _walnut),
    ];

    final visible = _visible;
    if (visible.isEmpty && _activeFilter != SuggestionFilter.all) {
      return const SizedBox.shrink();
    }
    final display = visible.isEmpty ? widget.suggestions : visible;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _walnut.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: const BoxDecoration(
                color: _headerBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _walnut,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suggested for You',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF5D4037),
                          ),
                        ),
                        Text(
                          'Based on your activity',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: widget.onSeeAll,
                    child: Text(
                      'See all',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _walnut,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: chips.map((chip) {
                  final selected = _activeFilter == chip.filter;
                  return GestureDetector(
                    onTap: () => setState(() => _activeFilter = selected ? SuggestionFilter.all : chip.filter),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: chip.color.withValues(alpha: selected ? 0.18 : 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: chip.color.withValues(alpha: selected ? 0.5 : 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(chip.icon, size: 14, color: chip.color),
                          const SizedBox(width: 6),
                          Text(
                            chip.label,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: chip.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 248,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                scrollDirection: Axis.horizontal,
                itemCount: display.length.clamp(0, 12),
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final suggestion = display[index];
                  return _SuggestionCard(
                    suggestion: suggestion,
                    formatPrice: _formatPrice,
                    onTap: () => widget.onProductTap(suggestion.product),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipData {
  const _ChipData(this.label, this.filter, this.icon, this.color);
  final String label;
  final SuggestionFilter filter;
  final IconData icon;
  final Color color;
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.formatPrice,
    required this.onTap,
  });

  final ProductSuggestion suggestion;
  final String Function(double) formatPrice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final product = suggestion.product;
    final imageUrl = product.imageUrls.isNotEmpty
        ? ModelPathHelper.normalize(product.imageUrls.first)
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    color: const Color(0xFFF5F0EB),
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              CupertinoIcons.cube_box,
                              color: Color(0xFF8D6E63),
                              size: 36,
                            ),
                          )
                        : const Icon(
                            CupertinoIcons.cube_box,
                            color: Color(0xFF8D6E63),
                            size: 36,
                          ),
                  ),
                ),
                if (suggestion.badge != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: suggestion.badge == 'New'
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF8D6E63),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        suggestion.badge!,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Text(
                suggestion.reason,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8D6E63),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: Text(
                product.name,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Row(
                children: [
                  Text(
                    '₱${formatPrice(product.price)}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < product.rating.round().clamp(0, 5)
                            ? CupertinoIcons.star_fill
                            : CupertinoIcons.star,
                        size: 11,
                        color: const Color(0xFFFFC107),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
