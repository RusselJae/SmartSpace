import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:firebase_core/firebase_core.dart';

import 'screens/admin/admin_shell.dart';
import 'screens/admin/auth/admin_login_page.dart';
import 'screens/admin/auth/admin_signup_page.dart';
import 'screens/admin/auth/admin_password_reset_screen.dart';
import 'screens/views/verify_email_screen.dart';
import 'screens/profile/how_to_order_screen.dart';
import 'screens/profile/terms_and_conditions_screen.dart';
import 'screens/profile/privacy_policy_screen.dart';
import 'screens/profile/security_privacy_screen.dart';
import 'screens/profile/change_password_screen.dart';
import 'utils/env_loader.dart';
import 'utils/admin_url_strategy.dart';
import 'services/mysql_database_service.dart';
import 'config/database_config.dart';

/// Admin-only Flutter entrypoint.
///
/// Build for web (Cloudflare Pages, etc.):
///   flutter build web --release --target lib/main_admin.dart
///
/// Default [main.dart] stays for Play Store / customer Android—do not pass
/// `--target lib/main_admin.dart` for that build.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Use `/#/admin/...` on web so each panel has a stable, shareable URL.
  configureAdminUrlStrategy();

  try {
    await EnvLoader.load();
  } catch (e) {
    // Continue even if .env file is missing (web often uses index.html config).
  }

  try {
    final apiKey = EnvLoader.get('FIREBASE_API_KEY');
    final appId = EnvLoader.get('FIREBASE_APP_ID');
    final messagingSenderId = EnvLoader.get('FIREBASE_MESSAGING_SENDER_ID');
    final projectId = EnvLoader.get('FIREBASE_PROJECT_ID');
    final storageBucket = EnvLoader.get('FIREBASE_STORAGE_BUCKET');

    if (apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          storageBucket: storageBucket.isNotEmpty ? storageBucket : '$projectId.appspot.com',
        ),
      );
      developer.log('✅ Firebase initialized (admin web)');
    }
  } catch (e) {
    developer.log('⚠️ Firebase init skipped or failed (admin): $e');
  }

  try {
    DatabaseConfig.printConfig();
  } catch (e) {
    // Non-fatal.
  }

  unawaited(() async {
    try {
      final db = MySQLDatabaseService();
      await db.initialize();
      developer.log('✅ Admin app: API/database layer initialized');
    } catch (error) {
      developer.log('⚠️ Admin app: DB init issue: $error');
    }
  }());

  runApp(const WoodHomeAdminApp());
}

class WoodHomeAdminApp extends StatelessWidget {
  const WoodHomeAdminApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    const Color kTextPrimary = Color(0xFF6D4C41);
    const Color kBrown = Color(0xFF8D6E63);
    const Color kWalnut = Color(0xFF5C4033);
    const Color kOrange = Color(0xFFFF9800);
    const Color kSurface = Color(0xFFFFFBF7);

    String? poppins;
    try {
      poppins = GoogleFonts.poppins().fontFamily;
    } catch (e) {
      poppins = null;
    }

    final baseText = TextStyle(
      inherit: false,
      fontFamily: poppins,
      color: kTextPrimary,
    );

    final cupertinoTheme = CupertinoThemeData(
      primaryColor: kWalnut,
      barBackgroundColor: Colors.white,
      scaffoldBackgroundColor: Colors.white,
      textTheme: CupertinoTextThemeData(
        textStyle: baseText.copyWith(fontSize: 15),
        navTitleTextStyle: baseText.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        navLargeTitleTextStyle: baseText.copyWith(fontSize: 32, fontWeight: FontWeight.w700),
        tabLabelTextStyle: baseText.copyWith(fontSize: 12),
        pickerTextStyle: baseText,
      ),
    );

    final baseColorScheme = ColorScheme.fromSeed(
      seedColor: kBrown,
      brightness: Brightness.light,
    ).copyWith(
      primary: kBrown,
      secondary: kOrange,
      surface: kSurface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wood Home Furniture Trading - Admin',
      scaffoldMessengerKey: scaffoldMessengerKey,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: baseColorScheme,
        scaffoldBackgroundColor: Colors.white,
        textTheme: poppins != null
            ? GoogleFonts.poppinsTextTheme().apply(
                  bodyColor: kTextPrimary,
                  displayColor: kTextPrimary,
                )
            : ThemeData.light().textTheme.apply(
                  bodyColor: kTextPrimary,
                  displayColor: kTextPrimary,
                ),
      ),
      builder: (context, child) {
        if (child == null) {
          return const Material(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return CupertinoTheme(
          data: cupertinoTheme,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFFBF7), Color(0xFFFFFFFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.3],
              ),
            ),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: child,
            ),
          ),
        );
      },
      // Start at admin login; no customer shell or onboarding in this entrypoint.
      initialRoute: AdminLoginPage.route,
      routes: {
        ...buildAdminShellRoutes(),
        AdminLoginPage.route: (_) => const AdminLoginPage(),
        AdminSignupPage.route: (_) => const AdminSignupPage(),
        VerifyEmailScreen.route: (context) {
          final uri = Uri.base;
          final token = uri.queryParameters['token'];
          return VerifyEmailScreen(token: token);
        },
        AdminPasswordResetScreen.route: (context) {
          final uri = Uri.base;
          final token = uri.queryParameters['token'];
          return AdminPasswordResetScreen(token: token);
        },
        TermsAndConditionsScreen.route: (_) => const TermsAndConditionsScreen(),
        HowToOrderScreen.route: (_) => const HowToOrderScreen(),
        PrivacyPolicyScreen.route: (_) => const PrivacyPolicyScreen(),
        SecurityPrivacyScreen.route: (_) => const SecurityPrivacyScreen(),
        ChangePasswordScreen.route: (_) => const ChangePasswordScreen(),
      },
    );
  }
}
