import '../screens/admin/admin_routes.dart';

/// Non-web platforms ignore hash; always open overview after login.
String readAdminPostLoginTargetPath() => AdminRoutes.dashboard;
