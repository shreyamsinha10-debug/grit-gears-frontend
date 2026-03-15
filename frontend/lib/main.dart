// ---------------------------------------------------------------------------
// Jupiter Arena – Flutter app entry and shell.
// ---------------------------------------------------------------------------
// This file: (1) initializes the app and date formatting, (2) holds [MyApp]
// for theme (light/dark) and [_InitialRoute] which shows LoginScreen or
// ResetPasswordScreen (when URL has ?token=). After login, role/phone decide
// Admin Dashboard vs Member Home.
// Theme preference is persisted via [SecureStorage]; server URL via SharedPreferences.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api_client.dart';
import 'core/secure_storage.dart';
import 'core/theme_changer_scope.dart';
import 'core/url_token_helper.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en');
  final prefs = await SharedPreferences.getInstance();
  await ApiClient.loadSavedBaseUrl(() async => prefs.getString(ApiClient.prefsKey));
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    SecureStorage.getThemeDark().then((dark) {
      if (mounted) setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
    });
  }

  void setThemeDark(bool dark) {
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
    SecureStorage.setThemeDark(dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: defaultGymName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      // Key by theme so the home subtree is recreated on theme switch, avoiding
      // "GlobalKey used multiple times" (ink renderer) when theme changes.
      home: ThemeChangerScope(
        setThemeDark: (dark) => setThemeDark(dark),
        child: KeyedSubtree(
          key: ValueKey<ThemeMode>(_themeMode),
          child: const _InitialRoute(),
        ),
      ),
    );
  }
}

/// Decides first screen: ResetPasswordScreen if URL has ?token= (e.g. from email link), else LoginScreen.
class _InitialRoute extends StatelessWidget {
  const _InitialRoute();

  @override
  Widget build(BuildContext context) {
    final token = getResetTokenFromUrl();
    if (token != null && token.isNotEmpty) {
      return ResetPasswordScreen(token: token);
    }
    return const LoginScreen();
  }
}

