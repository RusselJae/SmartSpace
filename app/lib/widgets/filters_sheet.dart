import 'package:flutter/cupertino.dart';

class FiltersSheet extends StatefulWidget {
  const FiltersSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showCupertinoModalPopup(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (context) => const FiltersSheet(),
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
  double _minPrice = 50;
  double _maxPrice = 900;

  // Style and material chips
  final Set<String> _styles = <String>{};
  final Set<String> _materials = <String>{};
  final Set<Color> _colors = <Color>{};
  String _size = 'M';

  @override
  void initState() {
    super.initState();
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
                      const Text('Filters', style: TextStyle(inherit: true, fontSize: 18, fontWeight: FontWeight.w700)),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        onPressed: _reset,
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Price range', style: TextStyle(inherit: true)),
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
                      Text('\$${_minPrice.toStringAsFixed(0)}', style: const TextStyle(inherit: true)),
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
                      Text('\$${_maxPrice.toStringAsFixed(0)}', style: const TextStyle(inherit: true)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Style', style: TextStyle(inherit: true)),
                  const SizedBox(height: 6),
                  _Chips(
                    options: const ['Modern', 'Classic', 'Minimal', 'Industrial'],
                    selected: _styles,
                    onToggle: (s) => setState(() => _styles.toggle(s)),
                  ),
                  const SizedBox(height: 8),
                  const Text('Material', style: TextStyle(inherit: true)),
                  const SizedBox(height: 6),
                  _Chips(
                    options: const ['Wood', 'Metal', 'Fabric', 'Leather'],
                    selected: _materials,
                    onToggle: (s) => setState(() => _materials.toggle(s)),
                  ),
                  const SizedBox(height: 8),
                  const Text('Color', style: TextStyle(inherit: true)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in const [
                        Color(0xFF4E342E), // dark brown
                        Color(0xFF6D4C41), // brown
                        Color(0xFFBCAAA4), // light brown
                        Color(0xFF000000),
                        Color(0xFFFFFFFF),
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
                  const Text('Size', style: TextStyle(inherit: true)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final s in const ['S', 'M', 'L'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            color: _size == s ? const Color(0xFFBCAAA4) : CupertinoColors.systemGrey5,
                            onPressed: () => setState(() => _size = s),
                            child: Text(s, style: const TextStyle(inherit: true, color: Color(0xFF4E342E))),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          color: CupertinoColors.systemGrey5,
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CupertinoButton.filled(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Apply Filters'),
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
            color: selected.contains(o) ? const Color(0xFFBCAAA4) : CupertinoColors.systemGrey5,
            onPressed: () => onToggle(o),
            child: Text(o, style: const TextStyle(inherit: true, color: Color(0xFF4E342E))),
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
            color: selected ? const Color(0xFF4E342E) : CupertinoColors.separator,
            width: 2,
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


