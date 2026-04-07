import 'package:flutter_web_plugins/url_strategy.dart';

/// Admin web uses `/#/admin/...` so static hosts and refreshes resolve reliably.
void configureAdminUrlStrategy() {
  setUrlStrategy(HashUrlStrategy());
}
