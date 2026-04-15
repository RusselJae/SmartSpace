import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Renders legal page content from a simple text format:
///
/// - `## Section Title` – section header
/// - `**Label**` – bold sublabel
/// - `- Bullet point` – bullet item
/// - Plain text – body paragraph
///
/// Blank lines add spacing. Used for Terms & Conditions and Privacy Policy
/// when content is loaded from the backend.
class LegalContentRenderer extends StatelessWidget {
  const LegalContentRenderer({
    super.key,
    required this.content,
    this.header,
    this.dividerColor = const Color(0xFFE0D4C8),
  });

  final String content;
  final Widget? header;
  final Color dividerColor;

  static const Color _mediumBrown = Color(0xFF8D6E63);

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(content);
    final children = <Widget>[
      if (header != null) ...[
        header!,
        const SizedBox(height: 12),
      ],
      ...blocks.asMap().entries.map((e) => _buildBlock(e.value, e.key)),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: children,
    );
  }

  List<_Block> _parse(String text) {
    final blocks = <_Block>[];
    final lines = text.split('\n');
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      if (trimmed.startsWith('## ')) {
        blocks.add(_Block(type: _BlockType.section, text: trimmed.substring(3)));
        i++;
        continue;
      }

      if (trimmed.startsWith('**') && trimmed.endsWith('**') && trimmed.length > 4) {
        blocks.add(_Block(
          type: _BlockType.label,
          text: trimmed.substring(2, trimmed.length - 2),
        ));
        i++;
        continue;
      }

      if (trimmed.startsWith('- ')) {
        blocks.add(_Block(type: _BlockType.bullet, text: trimmed.substring(2)));
        i++;
        continue;
      }

      // Body paragraph – collect until blank or next ## / - / **
      final buffer = StringBuffer(trimmed);
      i++;
      while (i < lines.length) {
        final next = lines[i];
        final nextTrimmed = next.trim();
        if (nextTrimmed.isEmpty ||
            nextTrimmed.startsWith('## ') ||
            nextTrimmed.startsWith('- ') ||
            (nextTrimmed.startsWith('**') && nextTrimmed.endsWith('**'))) {
          break;
        }
        buffer.write(' ');
        buffer.write(nextTrimmed);
        i++;
      }
      blocks.add(_Block(type: _BlockType.body, text: buffer.toString()));
    }

    return blocks;
  }

  Widget _buildBlock(_Block block, int index) {
    switch (block.type) {
      case _BlockType.section:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) ...[
              const SizedBox(height: 18),
              Divider(color: dividerColor, height: 24),
            ],
            _sectionTitle(block.text),
            const SizedBox(height: 6),
          ],
        );
      case _BlockType.label:
        return _label(block.text);
      case _BlockType.bullet:
        return _bullet(block.text);
      case _BlockType.body:
        return _bodyText(block.text);
    }
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: _mediumBrown,
      ),
    );
  }

  Widget _bodyText(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 14,
        color: Colors.black87,
        height: 1.4,
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14, height: 1.4)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _BlockType { section, label, bullet, body }

class _Block {
  _Block({required this.type, required this.text});
  final _BlockType type;
  final String text;
}
