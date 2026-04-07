import 'package:shared_preferences/shared_preferences.dart';

/// Whether the customer has finished the intro carousel (Get started).
/// Independent of auth: signed-in users still see onboarding once per install
/// until they complete it.
class OnboardingStorage {
  OnboardingStorage._();

  static const String _key = 'smartspace.onboarding_complete';

  static Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
