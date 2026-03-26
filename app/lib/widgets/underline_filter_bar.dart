import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// UnderlineFilterBar
//
// Horizontal, single-line filter control: default **black** labels; **walnut**
// when selected or hovered; **bottom border only** when selected (Apple-style
// clarity, minimal chrome). Springy color transitions for a polished feel.
// =============================================================================

/// One filter segment: stable [key] for selection, [label] for display.
class UnderlineFilterEntry {
  const UnderlineFilterEntry({required this.key, required this.label});

  final String key;
  final String label;
}

class UnderlineFilterBar extends StatelessWidget {
  const UnderlineFilterBar({
    super.key,
    required this.entries,
    required this.selectedKey,
    required this.onSelect,
    this.walnut = const Color(0xFF5C4033),
    this.horizontalPadding = 0,
    this.itemGap = 16,
  });

  final List<UnderlineFilterEntry> entries;
  final String selectedKey;
  final ValueChanged<String> onSelect;

  /// Brand walnut (active + hover); aligns with shell / catalog.
  final Color walnut;
  final double horizontalPadding;
  final double itemGap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) SizedBox(width: itemGap),
            _UnderlineFilterTile(
              label: entries[i].label,
              selected: selectedKey == entries[i].key,
              onTap: () => onSelect(entries[i].key),
              walnut: walnut,
            ),
          ],
        ],
      ),
    );
  }
}

class _UnderlineFilterTile extends StatefulWidget {
  const _UnderlineFilterTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.walnut,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color walnut;

  @override
  State<_UnderlineFilterTile> createState() => _UnderlineFilterTileState();
}

class _UnderlineFilterTileState extends State<_UnderlineFilterTile> {
  bool _hover = false;

  static const Color _inkBlack = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final Color fg = selected || _hover ? widget.walnut : _inkBlack;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.only(top: 6, bottom: 8, left: 2, right: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? widget.walnut : Colors.transparent,
                width: selected ? 2 : 0,
              ),
            ),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: fg,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
