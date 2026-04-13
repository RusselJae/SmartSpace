/// Parses `smartspace://paymongo-return?...` after PayMongo redirects to the API return page.
class PaymongoReturnDeepLink {
  PaymongoReturnDeepLink._();

  static PaymongoReturnArgs? tryParseUri(Uri uri) {
    if (uri.scheme != 'smartspace') return null;
    if (uri.host != 'paymongo-return') return null;
    final status = uri.queryParameters['status'];
    if (status != 'success' && status != 'cancel') return null;
    return PaymongoReturnArgs(
      isSuccess: status == 'success',
      orderId: uri.queryParameters['orderId'],
      mtoRequestId: uri.queryParameters['mtoRequestId'],
    );
  }

  static PaymongoReturnArgs? tryParse(String url) {
    try {
      return tryParseUri(Uri.parse(url));
    } catch (_) {
      return null;
    }
  }
}

class PaymongoReturnArgs {
  const PaymongoReturnArgs({
    required this.isSuccess,
    this.orderId,
    this.mtoRequestId,
  });

  final bool isSuccess;
  final String? orderId;
  final String? mtoRequestId;
}
