// ---------------------------------------------------------------------------
// Jupiter Arena – Flutter app entry and shell.
// ---------------------------------------------------------------------------
// This file: (1) initializes the app and date formatting, (2) holds [MyApp]
// for theme (light/dark) and [MyHomePage] which decides the initial route:
// Login, Admin Dashboard, or Member Home based on stored role/phone.
// Theme preference is persisted via [SecureStorage]; server URL via SharedPreferences.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api_client.dart';
import 'core/app_constants.dart';
import 'core/secure_storage.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en');
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
      home: KeyedSubtree(
        key: ValueKey<ThemeMode>(_themeMode),
        child: MyHomePage(title: defaultGymName, onThemeChanged: setThemeDark),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, this.onThemeChanged});

  final String title;
  final void Function(bool dark)? onThemeChanged;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isPinging = false;

  @override
  void initState() {
    super.initState();
    ApiClient.loadSavedBaseUrl(() async =>
        (await SharedPreferences.getInstance()).getString(ApiClient.prefsKey))
        .then((_) {
      if (mounted) setState(() {});
      _checkUpdate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage(defaultLogoAsset), context);
    });
  }

  /// Returns true if current version is strictly less than required (e.g. 1.0.0 < 1.0.1).
  static bool _isVersionOlder(String current, String required) {
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final r = required.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < c.length || i < r.length; i++) {
      final cv = i < c.length ? c[i] : 0;
      final rv = i < r.length ? r[i] : 0;
      if (cv < rv) return true;
      if (cv > rv) return false;
    }
    return false;
  }

  Future<void> _checkUpdate() async {
    try {
      final r = await ApiClient.instance.get('/version', useCache: false);
      if (r.statusCode != 200 || !mounted) return;
      final body = jsonDecode(r.body) as Map<String, dynamic>?;
      final minVer = body?['min_app_version']?.toString();
      if (minVer == null || minVer.isEmpty) return;
      if (!_isVersionOlder(kAppVersion, minVer)) return;
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Update required'),
          content: const Text(
            'A new version of the app is available. Please update from the Play Store to continue.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> _showSetServerUrlDialog() async {
    final controller = TextEditingController(text: ApiClient.baseUrl);
    if (!mounted) return;
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set server URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://your-backend.up.railway.app',
            border: OutlineInputBorder(),
          ),
          autocorrect: false,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated != true || !mounted) return;
    final url = controller.text.trim();
    if (url.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ApiClient.prefsKey, url);
    ApiClient.overrideBaseUrl = url;
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Server URL set to $url')),
    );
  }

  Future<void> _pingServer() async {
    if (_isPinging) return;
    setState(() => _isPinging = true);

    try {
      final response = await ApiClient.instance.get('/', useCache: false);

      if (!mounted) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = data['message'] as String? ?? 'Gym API is Live!';
      final backend = data['backend'] as String?;
      final displayMessage = backend != null ? '$message ($backend)' : message;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF0D0D0D), size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text(displayMessage)),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final url = ApiClient.baseUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Color(0xFF0D0D0D), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Server unreachable. URL: $url — ${e.toString().split('\n').first}'),
              ),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _isPinging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _AppLogo(size: 40),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(widget.title),
        ),
        actions: [
          if (widget.onThemeChanged != null)
            Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return IconButton(
                  icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                  tooltip: isDark ? 'Light mode' : 'Dark mode',
                  onPressed: () => widget.onThemeChanged!(!isDark),
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              ApiClient.baseUrl,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          TextButton(
                            onPressed: _showSetServerUrlDialog,
                            child: const Text('Set server URL'),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      icon: const Icon(Icons.login_rounded, size: 22),
                      label: const Text('Sign In'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _isPinging ? null : _pingServer,
                      icon: _isPinging
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find, size: 20),
                      label: Text(_isPinging ? 'Pinging...' : 'Ping server'),
                    ),
                    // Version and credit visible on mobile (below main content, inside scroll)
                    const SizedBox(height: 32),
                    Text(
                      'GS 1.1 (03 Mar 2026)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Powered By Dertz Infotech',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
          // Bottom-right version (for web/wide layout; mobile uses inline version above)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'GS 1.1 (03 Mar 2026)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Powered By Dertz Infotech',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Default app logo (Grit & Gears); asset or placeholder.
class _AppLogo extends StatelessWidget {
  final double size;

  const _AppLogo({this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      defaultLogoAsset,
      height: size,
      width: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.fitness_center, color: AppTheme.primary, size: size * 0.6),
      ),
    );
  }
}
