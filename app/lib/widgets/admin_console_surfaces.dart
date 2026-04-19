import 'package:flutter/material.dart';

/// Shared card surfaces for admin detail modals and lists, aligned with
/// [AdminProfilePage] bordered panels (white fill, soft grey stroke, ~22px radius).
class AdminConsoleSurfaces {
  AdminConsoleSurfaces._();

  static const double detailCardRadius = 22;

  static const EdgeInsets detailCardPadding = EdgeInsets.fromLTRB(24, 22, 24, 26);

  static BoxDecoration detailCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(detailCardRadius),
      border: Border.all(color: Colors.grey.shade200),
    );
  }

  /// Standard bordered panel used inside scroll areas on admin detail dialogs.
  static Widget detailCard({required Widget child}) {
    return Container(
      decoration: detailCardDecoration(),
      padding: detailCardPadding,
      child: child,
    );
  }
}
