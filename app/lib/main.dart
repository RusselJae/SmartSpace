import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/onboarding/onboarding_flow.dart';
import 'screens/shell/tab_shell.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/admin/auth/admin_login_page.dart';
import 'screens/admin/auth/admin_signup_page.dart';

void main() {
  runApp(const SmartSpaceApp());
}

class SmartSpaceApp extends StatelessWidget {
  const SmartSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color kDarkBrown = Color(0xFF3E2723);
    const Color kBrown = Color(0xFF5D4037);
    const Color kSand = Color(0xFFF4E6D4);
    const Color kSurface = Color(0xFFFFFBF7);

    final String poppins = GoogleFonts.poppins().fontFamily!;

    final baseText = TextStyle(
      fontFamily: poppins,
      color: kDarkBrown,
    );

    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartSpace AR',
      theme: CupertinoThemeData(
        primaryColor: kBrown,
        barBackgroundColor: kSurface,
        scaffoldBackgroundColor: kSand,
        textTheme: CupertinoTextThemeData(
          textStyle: baseText.copyWith(fontSize: 15),
          navTitleTextStyle: baseText.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          navLargeTitleTextStyle: baseText.copyWith(fontSize: 32, fontWeight: FontWeight.w700),
          tabLabelTextStyle: baseText.copyWith(fontSize: 12),
          pickerTextStyle: baseText,
        ),
      ),
      home: const OnboardingFlow(),
      routes: {
        TabShell.route: TabShell.builder,
        AdminShell.route: (_) => const AdminShell(),
        AdminLoginPage.route: (_) => const AdminLoginPage(),
        AdminSignupPage.route: (_) => const AdminSignupPage(),
      },
    );
  }
}
