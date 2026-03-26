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
    return minPrice > 1 ||
        maxPrice < 100000 ||
        styles.isNotEmpty ||
        materials.isNotEmpty ||
        colors.isNotEmpty ||
        size != 'M';
  }
}

const Color _kWalnut = Color(0xFF5C4033);

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
    _minPrice = initial?.minPrice ?? 1;
    _maxPrice = initial?.maxPrice ?? 100000;
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
      _minPrice = 1;
      _maxPrice = 100000;
      _styles.clear();
      _materials.clear();
      _colors.clear();
      _size = 'M';
    });
  }

  String _formatPesos(int amount) {
    final text = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final isBoundary = i > 0 && (text.length - i) % 3 == 0;
      if (isBoundary) buffer.write(',');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  static const List<_LabeledColor> _adminProductColors = [
    // Keep in sync with admin add/edit common colors.
    _LabeledColor(color: Color(0xFF8D6E63), label: 'Brown'),
    _LabeledColor(color: Color(0xFF212121), label: 'Black'),
    _LabeledColor(color: Color(0xFFFFFFFF), label: 'White'),
    _LabeledColor(color: Color(0xFFBCAAA4), label: 'Light Brown'),
    _LabeledColor(color: Color(0xFF5D4037), label: 'Dark Brown'),
    _LabeledColor(color: Color(0xFFD7CCC8), label: 'Natural'),
    _LabeledColor(color: Color(0xFF9E9E9E), label: 'Gray'),
    _LabeledColor(color: Color(0xFFF5F5DC), label: 'Beige'),
  ];

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
                  RangeSlider(
                    min: 1,
                    max: 100000,
                    values: RangeValues(
                      _minPrice.clamp(1, 100000),
                      _maxPrice.clamp(1, 100000),
                    ),
                    onChanged: (values) {
                      setState(() {
                        _minPrice = values.start.clamp(1, 100000);
                        _maxPrice = values.end.clamp(_minPrice, 100000);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  // Single-line combined price range display.
                  Text(
                    '₱${_formatPesos(_minPrice.toInt())} - ₱${_formatPesos(_maxPrice.toInt())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                    // Keep style options in sync with admin product form
                    options: const ['Modern', 'Classic', 'Minimal', 'Traditional'],
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
                    // Restrict materials to the four supported species
                    options: const ['Mahogany', 'Acacia', 'Molave', 'Yakal'],
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
                  _ColorDotPicker(
                    options: _adminProductColors,
                    selected: _colors,
                    onToggle: (c) => setState(() {
                      if (_colors.contains(c)) {
                        _colors.remove(c);
                      } else {
                        _colors.add(c);
                      }
                    }),
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
                            padding: EdgeInsets.zero,
                            borderRadius: BorderRadius.zero,
                            onPressed: () => setState(() => _size = s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: _size == s ? _kWalnut : Colors.white,
                                borderRadius: BorderRadius.zero,
                                border: Border.all(color: _kWalnut, width: 1),
                              ),
                              child: Text(
                                s,
                                style: GoogleFonts.poppins(
                                  color: _size == s ? Colors.white : _kWalnut,
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  decoration: TextDecoration.none,
                                ),
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
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.zero,
                            border: Border.all(color: _kWalnut, width: 1),
                          ),
                          child: CupertinoButton(
                            borderRadius: BorderRadius.zero,
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.poppins(
                                color: _kWalnut,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: _kWalnut,
                            borderRadius: BorderRadius.zero,
                            border: Border.all(color: _kWalnut, width: 1),
                          ),
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            borderRadius: BorderRadius.zero,
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

class _LabeledColor {
  const _LabeledColor({required this.color, required this.label});
  final Color color;
  final String label;
}

class _ColorDotPicker extends StatelessWidget {
  const _ColorDotPicker({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<_LabeledColor> options;
  final Set<Color> selected;
  final void Function(Color) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final opt in options)
          Tooltip(
            message: opt.label,
            child: GestureDetector(
              onTap: () => onToggle(opt.color),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: opt.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected.contains(opt.color) ? _kWalnut : CupertinoColors.separator,
                    width: selected.contains(opt.color) ? 3 : 1.5,
                  ),
                  boxShadow: [
                    if (selected.contains(opt.color))
                      BoxShadow(
                        color: _kWalnut.withValues(alpha: 0.22),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
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
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.zero,
            onPressed: () => onToggle(o),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected.contains(o) ? _kWalnut : Colors.white,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: _kWalnut, width: 1),
              ),
              child: Text(
                o,
                style: GoogleFonts.poppins(
                  color: selected.contains(o) ? Colors.white : _kWalnut,
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
      ],
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


