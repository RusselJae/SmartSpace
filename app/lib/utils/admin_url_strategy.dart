import 'admin_url_strategy_stub.dart'
    if (dart.library.html) 'admin_url_strategy_web.dart' as url_strategy_impl;

void configureAdminUrlStrategy() => url_strategy_impl.configureAdminUrlStrategy();
