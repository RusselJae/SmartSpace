import 'admin_post_login_path_stub.dart'
    if (dart.library.html) 'admin_post_login_path_web.dart' as post_login_impl;

/// Resolves which admin route to open after sign-in (web reads `/#/admin/...`).
String adminPostLoginTargetPath() => post_login_impl.readAdminPostLoginTargetPath();
