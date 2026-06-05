/// Parses `support-form/{type}?request={id}` links from support chat messages.
class SupportFormLink {
  const SupportFormLink({required this.formType, required this.requestId});

  final String formType;
  final String requestId;

  static final RegExp _pattern = RegExp(
    r'support-form/([a-z0-9_]+)\?request=([a-zA-Z0-9_-]+)',
    caseSensitive: false,
  );

  static SupportFormLink? tryParseFromText(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    return SupportFormLink(
      formType: match.group(1)!,
      requestId: match.group(2)!,
    );
  }

  String get path => 'support-form/$formType?request=$requestId';
}
