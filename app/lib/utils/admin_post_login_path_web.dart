// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import '../screens/admin/admin_routes.dart';

/// Reads `window.location.hash` so a bookmark like `/#/admin/products` lands on the right tab after login.
String readAdminPostLoginTargetPath() {
  var hash = html.window.location.hash;
  if (hash.isEmpty || hash == '#') {
    return AdminRoutes.overview;
  }
  if (hash.startsWith('#')) {
    hash = hash.substring(1);
  }
  final path = AdminRoutes.normalizePath(hash);
  if (path == AdminRoutes.legacyShell) {
    return AdminRoutes.overview;
  }
  if (AdminRoutes.pathsByIndex.contains(path)) {
    return path;
  }
  return AdminRoutes.overview;
}
