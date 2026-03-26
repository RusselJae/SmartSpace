import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Toast notification utility for showing messages
/// 
/// Designed following Apple's Human Interface Guidelines with a sleek,
/// modern aesthetic. Features a two-section layout with header (icon, title,
/// timestamp, close button) and message body, positioned in the top right corner.
class Toast {
  /// Shows a custom toast notification
  /// 
  /// [context] - Build context for overlay access
  /// [message] - Main message to display
  /// [title] - Optional title (defaults to message type)
  /// [duration] - How long the toast should be visible
  /// [accentColor] - Accent color for icon and borders (defaults based on type)
  /// [icon] - Icon to display in the header
  static void show(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 4),
    Color? accentColor,
    IconData? icon,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    // Dismiss callback that removes the overlay entry
    void dismiss() {
      overlayEntry.remove();
    }
    
    overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        title: title,
        duration: duration,
        accentColor: accentColor ?? const Color(0xFF8D6E63),
        icon: icon,
        onDismiss: dismiss,
      ),
    );

    overlay.insert(overlayEntry);

    Future.delayed(duration, () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  /// Shows a success toast with green accent color
  /// 
  /// Uses a checkmark icon and green accent to indicate successful operations
  static void success(BuildContext context, String message, {String? title}) {
    show(
      context,
      message,
      title: title ?? 'Success',
      accentColor: const Color(0xFF4CAF50), // Green for success
      icon: CupertinoIcons.check_mark_circled_solid,
    );
  }

  /// Shows an error toast with red accent color
  /// 
  /// Uses an exclamation icon and red accent to indicate errors
  static void error(BuildContext context, String message, {String? title}) {
    show(
      context,
      message,
      title: title ?? 'Error',
      accentColor: const Color(0xFFF44336), // Red for errors
      icon: CupertinoIcons.exclamationmark_circle_fill,
    );
  }

  /// Shows an info toast with brown accent color
  /// 
  /// Uses an info icon and brown accent for informational messages
  static void info(BuildContext context, String message, {String? title}) {
    show(
      context,
      message,
      title: title ?? 'Info',
      accentColor: const Color(0xFF8D6E63), // Brown for info
      icon: CupertinoIcons.info_circle_fill,
    );
  }

  /// Shows a warning toast with orange accent color
  /// 
  /// Uses a warning icon and orange accent for warnings
  static void warning(BuildContext context, String message, {String? title}) {
    show(
      context,
      message,
      title: title ?? 'Warning',
      accentColor: const Color(0xFFFF9800), // Orange for warnings
      icon: CupertinoIcons.exclamationmark_triangle_fill,
    );
  }
}

/// Internal widget that renders the toast notification
/// 
/// Implements a two-section design with header and body, following
/// Apple's Human Interface Guidelines for modern, sleek notifications.
class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.message,
    this.title,
    required this.duration,
    required this.accentColor,
    this.icon,
    required this.onDismiss,
  });

  final String message;
  final String? title;
  final Duration duration;
  final Color accentColor;
  final IconData? icon;
  final VoidCallback onDismiss;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    // Spring animation controller for smooth, natural motion
    // Following Apple HIG principles for fluid animations
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Slide animation from right (top right corner entry)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0), // Start from right
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic, // Smooth easing
    ));

    // Fade animation for smooth appearance
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Subtle scale animation for polish
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    // Start animation
    _controller.forward();

    // Auto-dismiss after duration (with fade out)
    Future.delayed(widget.duration - const Duration(milliseconds: 300), () {
      if (mounted) {
        _controller.reverse().then((_) {
          // Remove from overlay after animation completes
          widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Handles manual dismissal via close button
  /// 
  /// Animates out and then removes the overlay entry
  void _dismiss() {
    _controller.reverse().then((_) {
      // Remove from overlay after animation completes
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // Position in top right corner with safe area padding
      top: MediaQuery.of(context).padding.top + 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Material(
              color: Colors.transparent,
              child: Container(
                // Fixed width for consistent appearance
                // Responsive to screen size but with max constraint
                // For mobile: use 80% width, for larger screens: max 320px
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width > 600 
                      ? 320 
                      : MediaQuery.of(context).size.width * 0.8,
                  minWidth: 240,
                ),
                decoration: BoxDecoration(
                  // Dominant white background as requested
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  // Subtle border with accent color for visual interest
                  border: Border.all(
                    color: widget.accentColor.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  // Soft shadow for depth following Apple HIG
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: widget.accentColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          widget.icon ?? CupertinoIcons.info_circle_fill,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF1A1A1A),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _dismiss,
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 14,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
