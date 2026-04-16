import 'package:flutter/material.dart';

/// Small anchored popover that appears *under* an icon/button.
///
/// Used for admin filter UI so it feels like a dropdown (not a bottom sheet).
/// This matches the notifications floating panel interaction pattern.
class AdminAnchoredPopover {
  static Future<T?> show<T>({
    required BuildContext context,
    required GlobalKey anchorKey,
    required Widget child,
    double width = 360,
    double height = 420,
    double screenPadding = 12,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(18)),
  }) {
    final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.sizeOf(context);

    double left = screenSize.width - width - screenPadding;
    double top = 72;

    if (box != null && box.hasSize) {
      final pos = box.localToGlobal(Offset.zero);
      final size = box.size;
      left = pos.dx + size.width / 2 - width / 2;
      if (left < screenPadding) left = screenPadding;
      if (left + width > screenSize.width - screenPadding) {
        left = screenSize.width - width - screenPadding;
      }
      top = pos.dy + size.height + 8;
    }

    if (top + height > screenSize.height - screenPadding) {
      top = screenSize.height - height - screenPadding;
    }
    if (top < 16) top = 16;

    return showDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.10),
      builder: (ctx) => SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(ctx).pop(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 28,
                shadowColor: Colors.black.withValues(alpha: 0.28),
                borderRadius: borderRadius,
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: SizedBox(width: width, height: height, child: child),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

