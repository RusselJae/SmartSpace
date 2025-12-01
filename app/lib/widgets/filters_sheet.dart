import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Filter data class to hold all filter values
class FilterData {
  final double minPrice;
  final double maxPrice;
  final Set<String> styles;
  final Set<String> materials;
  final Set<Color> colors;
  final String size;

  const FilterData({
    required this.minPrice,
    required this.maxPrice,
    required this.styles,
    required this.materials,
    required this.colors,
    required this.size,
  });

  /// Returns true if any filters are active (not default values)
  bool get hasActiveFilters {
    return minPrice > 50 ||
        maxPrice < 900 ||
        styles.isNotEmpty ||
        materials.isNotEmpty ||
        colors.isNotEmpty ||
        size != 'M';
  }
}

class FiltersSheet extends StatefulWidget {
  const FiltersSheet({super.key, this.initialFilters});

  /// Initial filter values to pre-populate the sheet
  final FilterData? initialFilters;

  /// Shows the filters sheet and returns the applied filter data
  static Future<FilterData?> show(BuildContext context, {FilterData? initialFilters}) {
    return showCupertinoModalPopup<FilterData>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (context) => FiltersSheet(initialFilters: initialFilters),
    );
  }

  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  // Price range (simple two-value slider surrogate)
  // Initialize from initialFilters if provided, otherwise use defaults
  late double _minPrice;
  late double _maxPrice;

  // Style and material chips
  late final Set<String> _styles;
  late final Set<String> _materials;
  late final Set<Color> _colors;
  late String _size;

  @override
  void initState() {
    super.initState();
    
    // Initialize filter values from initialFilters or defaults
    final initial = widget.initialFilters;
    _minPrice = initial?.minPrice ?? 50;
    _maxPrice = initial?.maxPrice ?? 900;
    _styles = Set<String>.from(initial?.styles ?? <String>{});
    _materials = Set<String>.from(initial?.materials ?? <String>{});
    _colors = Set<Color>.from(initial?.colors ?? <Color>{});
    _size = initial?.size ?? 'M';
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _minPrice = 50;
      _maxPrice = 900;
      _styles.clear();
      _materials.clear();
      _colors.clear();
      _size = 'M';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _opacity,
            child: Container(
              decoration: const BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filters',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        onPressed: _reset,
                        child: Text(
                          'Reset',
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 16,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Price range',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoSlider(
                          min: 0,
                          max: _maxPrice,
                          value: _minPrice.clamp(0, _maxPrice),
                          onChanged: (v) => setState(() => _minPrice = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₱${_minPrice.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoSlider(
                          min: _minPrice,
                          max: 2000,
                          value: _maxPrice.clamp(_minPrice, 2000),
                          onChanged: (v) => setState(() => _maxPrice = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₱${_maxPrice.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Style',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _Chips(
                    options: const ['Modern', 'Classic', 'Minimal', 'Industrial'],
                    selected: _styles,
                    onToggle: (s) => setState(() => _styles.toggle(s)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Material',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _Chips(
                    options: const ['Wood', 'Metal', 'Fabric', 'Leather'],
                    selected: _materials,
                    onToggle: (s) => setState(() => _materials.toggle(s)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Color',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Color palette: light brown to brown and orange tones
                      // Removed all dark brown variations for a warmer aesthetic
                      for (final c in const [
                        Color(0xFFD7CCC8), // very light brown
                        Color(0xFFBCAAA4), // light brown
                        Color(0xFFA1887F), // medium-light brown
                        Color(0xFF8D6E63), // medium brown
                        Color(0xFF6D4C41), // brown
                        Color(0xFFFFB74D), // light orange
                        Color(0xFFFF9800), // orange
                        Color(0xFFF57C00), // deeper orange
                      ])
                        _ColorDot(
                          color: c,
                          selected: _colors.contains(c),
                          onTap: () => setState(() {
                            if (_colors.contains(c)) {
                              _colors.remove(c);
                            } else {
                              _colors.add(c);
                            }
                          }),
                        )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Size',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final s in const ['S', 'M', 'L'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            // Light brown when inactive, normal brown when active
                            color: _size == s ? const Color(0xFF8D6E63) : const Color(0xFFBCAAA4),
                            onPressed: () => setState(() => _size = s),
                            child: Text(
                              s,
                              style: GoogleFonts.poppins(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          // Light brown for cancel button
                          color: const Color(0xFFBCAAA4),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.poppins(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8D6E63), Color(0xFFFF9800)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            borderRadius: BorderRadius.circular(12),
                            onPressed: () {
                            // Return the filter data when Apply is clicked
                            final filterData = FilterData(
                              minPrice: _minPrice,
                              maxPrice: _maxPrice,
                              styles: Set<String>.from(_styles),
                              materials: Set<String>.from(_materials),
                              colors: Set<Color>.from(_colors),
                              size: _size,
                            );
                            Navigator.of(context).pop(filterData);
                          },
                          child: Text(
                            'Apply Filters',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.options, required this.selected, required this.onToggle});
  final List<String> options;
  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            // Light brown when inactive, normal brown when active
            color: selected.contains(o) ? const Color(0xFF8D6E63) : const Color(0xFFBCAAA4),
            onPressed: () => onToggle(o),
            child: Text(
              o,
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? const Color(0xFF8D6E63) : CupertinoColors.separator,
            width: 2.5,
          ),
        ),
      ),
    );
  }
}

extension on Set<String> {
  void toggle(String value) {
    if (contains(value)) {
      remove(value);
    } else {
      add(value);
    }
  }
}


