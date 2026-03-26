import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:firebase_core/firebase_core.dart';

import 'screens/onboarding/onboarding_flow.dart';
import 'screens/shell/tab_shell.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/admin/auth/admin_login_page.dart';
import 'screens/admin/auth/admin_signup_page.dart';
import 'screens/views/verify_email_screen.dart';
import 'screens/profile/how_to_order_screen.dart';
import 'screens/profile/terms_and_conditions_screen.dart';
import 'screens/profile/privacy_policy_screen.dart';
import 'screens/profile/security_privacy_screen.dart';
import 'screens/profile/change_password_screen.dart';
import 'utils/env_loader.dart';
import 'services/mysql_database_service.dart';
import 'config/database_config.dart';
import 'services/auth_service.dart';
import 'widgets/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await EnvLoader.load();
  } catch (e) {
    // Continue even if .env file is missing
  }

  // Initialize Firebase
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
      developer.log('✅ Firebase initialized successfully');
    } else {
      developer.log('⚠️ Firebase credentials not found in .env file');
      developer.log('📝 Firebase Storage uploads will not work until Firebase is configured.');
    }
  } catch (e) {
    developer.log('⚠️ Firebase initialization failed: $e');
    developer.log('📝 Firebase Storage uploads will not work until Firebase is configured.');
  }
  
  try {
    // Print database configuration for debugging
    DatabaseConfig.printConfig();
  } catch (e) {
    // Continue even if config fails
  }
  
  // Initialize database connection in the background (non-blocking)
  // This will attempt to connect to MySQL, or fall back to mock data if unavailable
  unawaited(() async {
    try {
      final db = MySQLDatabaseService();
      await db.initialize();
      developer.log('✅ Database initialized successfully');
    } catch (error) {
      developer.log('⚠️  Database connection failed: $error');
      developer.log('📝 Using mock data. Check your .env file and MySQL server.');
    }
  }());
  
  runApp(const WoodHomeFurnitureApp());
}

class WoodHomeFurnitureApp extends StatelessWidget {
  const WoodHomeFurnitureApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    /// Color palette with light brown to brown and orange tones
    /// Following Apple's Human Interface Guidelines for a sleek, modern aesthetic
    const Color kTextPrimary = Color(0xFF6D4C41); // Medium brown for text
    const Color kBrown = Color(0xFF8D6E63); // Primary brown (legacy)
    const Color kWalnut = Color(0xFF5C4033); // Walnut (brand accent)
    const Color kOrange = Color(0xFFFF9800); // Primary orange (used in color scheme)
    const Color kSurface = Color(0xFFFFFBF7);

    /// We lean on Poppins everywhere so the typography feels consistent
    /// regardless of whether a widget is built with Material or Cupertino APIs.
    String? poppins;
    try {
      poppins = GoogleFonts.poppins().fontFamily;
    } catch (e) {
      poppins = null; // Fallback to system font
    }

    /// Base text style used for all Cupertino text definitions.
    /// Using medium brown for better readability while maintaining warmth
    final baseText = TextStyle(
      inherit: false,
      fontFamily: poppins,
      color: kTextPrimary,
    );

    /// Cupertino theme data so the interface keeps that sleek Apple-inspired
    /// aesthetic the design system calls for.
    final cupertinoTheme = CupertinoThemeData(
      // Ensures Cupertino back button + navigation accents match walnut across screens.
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

    /// Material color scheme primarily exists so Material widgets (like
    /// TextField) get proper theming AND the localization infrastructure
    /// they expect. This is what fixes the runtime error from the screenshot.
    /// Updated to use brown and orange tones without dark brown
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
      title: 'Wood Home Furniture Trading',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      /// Inject the delegates Material widgets require so we never see the
      /// "No MaterialLocalizations found" exception again.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
      ],
      /// ThemeData stays extremely light-touch so we preserve the bespoke look
      /// while ensuring Material widgets inherit coherent styling.
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
      /// The builder wraps everything back in a CupertinoTheme so the UI keeps
      /// following Apple's Human Interface Guidelines—minimal, calm, and sleek.
      builder: (context, child) {
        if (child == null) {
          return const Material(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return CupertinoTheme(
          data: cupertinoTheme,
          child: Container(
            // Enhanced background with subtle gradient following Apple HIG
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
      home: _AppInitializer(),
      routes: {
        TabShell.route: TabShell.builder,
        AdminShell.route: (_) => const AdminShell(),
        AdminLoginPage.route: (_) => const AdminLoginPage(),
        AdminSignupPage.route: (_) => const AdminSignupPage(),
        VerifyEmailScreen.route: (context) {
          // Extract token from URL query parameters
          final uri = Uri.base;
          final token = uri.queryParameters['token'];
          return VerifyEmailScreen(token: token);
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

/// Initializes the app and determines whether to show onboarding or main app
class _AppInitializer extends StatefulWidget {
  const _AppInitializer();

  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<_AppInitializer> {
  bool _isLoading = true;
  bool _showOnboarding = true;
  bool _authCheckComplete = false;
  bool _loadingScreenComplete = false;

  @override
  void initState() {
    super.initState();
    // Start the auth check in parallel with loading screen display
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    try {
      await AuthService().initializeSession();
      final auth = AuthService();
      if (mounted) {
        setState(() {
          _showOnboarding = !auth.isAuthenticated;
          _authCheckComplete = true;
          // Proceed if loading screen has also completed
          if (_loadingScreenComplete) {
            _isLoading = false;
          }
        });
      }
    } catch (e) {
      developer.log('⚠️ Failed to check auth state: $e');
      if (mounted) {
        setState(() {
          _showOnboarding = true;
          _authCheckComplete = true;
          // Proceed if loading screen has also completed
          if (_loadingScreenComplete) {
            _isLoading = false;
          }
        });
      }
    }
  }

  void _handleLoadingComplete() {
    // Called when LoadingScreen completes its 3-second display
    if (mounted) {
      setState(() {
        _loadingScreenComplete = true;
        // Proceed if auth check has also completed
        if (_authCheckComplete) {
          _isLoading = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // Show custom loading screen while checking auth state
      // LoadingScreen displays for 3 seconds, then calls onComplete
      return LoadingScreen(
        onComplete: _handleLoadingComplete,
      );
    }
    return _showOnboarding ? const OnboardingFlow() : const TabShell();
  }
}
