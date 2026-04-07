import 'dart:async';

import 'package:flutter/widgets.dart';

/// Root [Navigator] for the app. Kept separate from [main.dart] so services can
/// push routes when invoked from native code without import cycles.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Runs [action] once [appNavigatorKey] has a [NavigatorState] (e.g. after first frame).
Future<void> runWhenNavigatorReady(void Function(NavigatorState nav) action) async {
  for (var i = 0; i < 100; i++) {
    final nav = appNavigatorKey.currentState;
    if (nav != null) {
      action(nav);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
