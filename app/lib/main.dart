import 'dart:async';
import 'dart:developer' as developer;

import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'screens/views/password_reset_screen.dart';
import 'screens/admin/auth/admin_password_reset_screen.dart';
import 'screens/profile/how_to_order_screen.dart';
import 'screens/profile/terms_and_conditions_screen.dart';
import 'screens/profile/privacy_policy_screen.dart';
import 'screens/profile/security_privacy_screen.dart';
import 'screens/profile/change_password_screen.dart';
import 'screens/profile/notifications_center_screen.dart';
import 'utils/env_loader.dart';
import 'utils/deep_link_handler.dart';
import 'utils/paymongo_return_deep_link.dart';
import 'screens/checkout/success_screen.dart';
import 'app_nav.dart';
import 'services/mysql_database_service.dart';
import 'services/native_ar_editor_service.dart';
import 'config/database_config.dart';
import 'services/auth_service.dart';
import 'services/onboarding_storage.dart';
import 'services/catalog_model_prefetch.dart';
import 'services/push_notifications_service.dart';
import 'widgets/splash_screen.dart';

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

class WoodHomeFurnitureApp extends StatefulWidget {
  const WoodHomeFurnitureApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  State<WoodHomeFurnitureApp> createState() => _WoodHomeFurnitureAppState();
}

class _WoodHomeFurnitureAppState extends State<WoodHomeFurnitureApp> {
  StreamSubscription<Uri>? _appLinkSubscription;
  String? _lastHandledLink;
  DateTime? _lastHandledAt;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _appLinkSubscription = AppLinks().uriLinkStream.listen(_handleAppLink);
      AppLinks().getInitialLink().then(_handleAppLink);
    }
  }

  @override
  void dispose() {
    final sub = _appLinkSubscription;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  void _handleAppLink(Uri? uri) {
    if (uri == null) return;
    final url = uri.toString();
    final now = DateTime.now();
    if (_lastHandledLink == url &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastHandledLink = url;
    _lastHandledAt = now;

    final paymongo = PaymongoReturnDeepLink.tryParseUri(uri);
    if (paymongo != null) {
      unawaited(
        runWhenNavigatorReady((nav) {
          if (paymongo.isSuccess) {
            nav.push(
              CupertinoPageRoute<void>(
                builder: (_) {
                  final oid = paymongo.orderId;
                  final short = oid != null && oid.isNotEmpty
                      ? (oid.length > 8 ? oid.substring(0, 8) : oid).toUpperCase()
                      : null;
                  return SuccessScreen(
                    subtitle: short != null
                        ? 'Payment received. Order #$short will update in Orders.'
                        : 'Payment received. Check Orders for your latest status.',
                    invoiceOrderId: oid,
                  );
                },
              ),
            );
          } else {
            nav.push(
              CupertinoPageRoute<void>(
                builder: (_) => const SuccessScreen(
                  paymentCancelled: true,
                  subtitle:
                      'You can try checkout again from your cart or the Orders tab.',
                ),
              ),
            );
          }
        }),
      );
      return;
    }

    final token = DeepLinkHandler.extractVerificationToken(url);
    if (token == null) return;

    unawaited(
      runWhenNavigatorReady((nav) {
        nav.pushNamed(VerifyEmailScreen.route, arguments: token);
      }),
    );
  }

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
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: WoodHomeFurnitureApp._scaffoldMessengerKey,
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
        ...buildAdminShellRoutes(),
        AdminLoginPage.route: (_) => const AdminLoginPage(),
        AdminSignupPage.route: (_) => const AdminSignupPage(),
        VerifyEmailScreen.route: (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          String? token;
          if (args is String) {
            token = args;
          }
          if (kIsWeb && (token == null || token.isEmpty)) {
            token = Uri.base.queryParameters['token'];
          }
          return VerifyEmailScreen(token: token);
        },
        PasswordResetScreen.route: (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          String? token;
          if (args is String) {
            token = args;
          }
          if (kIsWeb && (token == null || token.isEmpty)) {
            token = Uri.base.queryParameters['token'];
          }
          return PasswordResetScreen(token: token);
        },
        AdminPasswordResetScreen.route: (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          String? token;
          if (args is String) {
            token = args;
          }
          if (kIsWeb && (token == null || token.isEmpty)) {
            token = Uri.base.queryParameters['token'];
          }
          return AdminPasswordResetScreen(token: token);
        },
        TermsAndConditionsScreen.route: (_) => const TermsAndConditionsScreen(),
        HowToOrderScreen.route: (_) => const HowToOrderScreen(),
        PrivacyPolicyScreen.route: (_) => const PrivacyPolicyScreen(),
        SecurityPrivacyScreen.route: (_) => const SecurityPrivacyScreen(),
        ChangePasswordScreen.route: (_) => const ChangePasswordScreen(),
        NotificationsCenterScreen.route: (_) => const NotificationsCenterScreen(),
      },
    );
  }
}

/// Cold start: splash -> onboarding until completed, then home. Auth runs during splash.
class _AppInitializer extends StatefulWidget {
  const _AppInitializer();

  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<_AppInitializer> {
  /// Stays true until auth, DB, optional model warm-up, and a minimum brand
  /// beat all complete — then onboarding or home is shown.
  bool _bootstrapComplete = false;
  bool _showOnboarding = true;
  bool _mustAcceptLatestTerms = false;
  int _latestTermsVersion = 1;

  @override
  void initState() {
    super.initState();
    // Native AR screen can invoke Flutter navigation while the engine runs.
    NativeArEditorService.registerNativeCallbacks();
    unawaited(_runColdStartBootstrap());
  }

  /// Returning users: also fill the GLB disk cache so the catalog opens hot.
  /// First-time users skip warm-up here and run it after onboarding instead.
  Future<void> _runColdStartBootstrap() async {
    final sw = Stopwatch()..start();
    bool onboardingDone = false;
    // When every model is already on disk, warm-up finishes in milliseconds; use a
    // shorter minimum splash so daily opens do not feel stuck on the logo.
    var prefetchWasQuick = false;

    try {
      await Future.wait([
        AuthService().initializeSession(),
        MySQLDatabaseService().initialize(),
      ]);
      await PushNotificationsService.instance.initialize();
      onboardingDone = await OnboardingStorage.isComplete();

      // Only block the cold splash for downloads when we are headed straight home.
      if (onboardingDone) {
        final prefetchSw = Stopwatch()..start();
        try {
          await CatalogModelPrefetch.warmCacheForStorefront()
              .timeout(const Duration(seconds: 90));
        } catch (e) {
          developer.log('⚠️ Model cache warm-up timed out or failed: $e');
        }
        prefetchSw.stop();
        prefetchWasQuick = prefetchSw.elapsedMilliseconds < 500;
      }
      final auth = AuthService();
      final user = auth.currentUser;
      if (onboardingDone && user != null) {
        final legal = await MySQLDatabaseService().getLegalContentPayload('terms');
        _latestTermsVersion = legal?.version ?? 1;
        final accepted = user.termsVersionAccepted ?? 0;
        _mustAcceptLatestTerms = accepted < _latestTermsVersion;
      }
    } catch (e) {
      developer.log('⚠️ Cold start bootstrap failed: $e');
      onboardingDone = false;
    }

    // First install / slow network: allow a longer beat. Cache-hot reopen: trim it.
    final minBrand = onboardingDone && prefetchWasQuick
        ? const Duration(milliseconds: 900)
        : const Duration(milliseconds: 2100);
    final rem = minBrand - sw.elapsed;
    if (rem > Duration.zero) {
      await Future.delayed(rem);
    }

    if (!mounted) return;
    setState(() {
      _showOnboarding = !onboardingDone;
      _bootstrapComplete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapComplete) {
      return const SplashScreen(
        footerHint: 'Signing in and loading your catalog…',
      );
    }
    if (_mustAcceptLatestTerms) {
      return _TermsAcceptanceGate(
        version: _latestTermsVersion,
        onAccepted: () async {
          await AuthService().acceptLatestTerms(_latestTermsVersion);
          if (!mounted) return;
          setState(() {
            _mustAcceptLatestTerms = false;
          });
        },
      );
    }
    return _showOnboarding ? const OnboardingFlow() : const TabShell();
  }
}

class _TermsAcceptanceGate extends StatelessWidget {
  const _TermsAcceptanceGate({required this.version, required this.onAccepted});

  final int version;
  final Future<void> Function() onAccepted;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Terms Update')),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Terms and Conditions v$version',
                style: GoogleFonts.poppins(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Before using account features, you must accept the latest terms update.',
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Open the full policy to review the updated clauses before accepting.',
                        style: GoogleFonts.poppins(fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          Navigator.of(context).pushNamed(TermsAndConditionsScreen.route);
                        },
                        child: Text(
                          'Read Terms & Conditions',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: () => onAccepted(),
                  child: Text(
                    'Accept latest terms',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
