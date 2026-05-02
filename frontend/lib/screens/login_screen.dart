// ---------------------------------------------------------------------------
// Login – unified entry: phone/email + password, routes to Admin or Member.
// ---------------------------------------------------------------------------
// Backend validates via POST /auth/login (super_admin, gym_admin, member).
// Fallback: member by phone (GET /members/by-phone) when login returns 401.
// Only existing accounts can sign in; no self-service gym creation.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/app_constants.dart';
import '../core/secure_storage.dart';
import '../core/theme_changer_scope.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard_screen.dart';
import 'member_home_screen.dart';
import 'sign_up_screen.dart';
import 'super_admin_screen.dart';

/// Single login screen: Email or Mobile + Password. Routes to Admin or Member based on credentials.
class LoginScreen extends StatefulWidget {
  /// Optional message to show (e.g. after portal access blocked for inactive member).
  final String? initialMessage;

  const LoginScreen({super.key, this.initialMessage});

  /// Call from any screen to clear auth and navigate back to login (e.g. logout button in AppBar).
  static Future<void> logout(BuildContext context) async {
    await SecureStorage.setAuthToken(null);
    ApiClient.setAuthToken(null);
    await SecureStorage.setAuthRole(null);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailOrPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  int _emailOrPhoneMaxLength = 10;  // 10 for phone, 50 for email

  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null && widget.initialMessage!.trim().isNotEmpty) {
      _error = widget.initialMessage;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(const AssetImage(defaultLogoAsset), context);
      _checkUpdate();
    });
  }

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

  @override
  void dispose() {
    _emailOrPhoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Extract phone (digits) for API lookup; fallback to trimmed input.
  String _toPhone(String input) {
    final t = input.trim();
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 10 ? digits : t;
  }

  void _showForgotPasswordDialog(
    BuildContext context,
    double padding,
    double radius,
    Color onSurface,
    Color surface,
    Color outline,
  ) {
    final controller = TextEditingController();
    bool loading = false;
    bool sent = false;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                'Forgot password?',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onSurface),
              ),
              content: SingleChildScrollView(
                child: sent
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.mark_email_read_outlined, color: AppTheme.primary, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'If an account exists for that email or phone, you’ll receive instructions shortly.',
                            style: GoogleFonts.poppins(fontSize: 14, color: onSurface),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enter your email or phone number. If a member account exists, we’ll send a reset link or temporary password to the email on file.',
                            style: GoogleFonts.poppins(fontSize: 14, color: onSurface),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: controller,
                            keyboardType: TextInputType.emailAddress,
                            maxLength: 50,
                            decoration: InputDecoration(
                              labelText: 'Email or phone',
                              hintText: 'e.g. you@example.com or 9876543210',
                              prefixIcon: const Icon(Icons.email_outlined, size: 22),
                              filled: true,
                              fillColor: surface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(radius),
                                borderSide: BorderSide(color: outline.withOpacity(0.6)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              counterText: '',
                            ),
                            style: GoogleFonts.poppins(color: onSurface),
                          ),
                        ],
                      ),
              ),
              actions: [
                if (sent)
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  )
                else ...[
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: loading
                        ? null
                        : () async {
                            final value = controller.text.trim();
                            if (value.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Enter your email or phone')),
                              );
                              return;
                            }
                            // If it looks like email, require @ and .
                            if (value.contains('@') && (!value.contains('.'))) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Please enter a valid email address')),
                              );
                              return;
                            }
                            setDialogState(() => loading = true);
                            try {
                              final res = await ApiClient.instance.post(
                                '/auth/forgot-password',
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({'email_or_phone': value}),
                              );
                              if (!ctx.mounted) return;
                              if (res.statusCode >= 200 && res.statusCode < 300) {
                                setDialogState(() { loading = false; sent = true; });
                              } else {
                                final body = jsonDecode(res.body) as Map<String, dynamic>?;
                                final detail = body?['detail']?.toString() ?? 'Request failed';
                                setDialogState(() => loading = false);
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(detail)),
                                );
                              }
                            } catch (e) {
                              if (!ctx.mounted) return;
                              setDialogState(() => loading = false);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Error: ${e.toString().split('\n').first}')),
                              );
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.onPrimary,
                    ),
                    child: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary),
                          )
                        : const Text('Send reset link'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _signIn() async {
    final emailOrPhone = _emailOrPhoneController.text.trim();
    final password = _passwordController.text.trim();

    if (emailOrPhone.isEmpty) {
      setState(() => _error = 'Enter email or mobile number');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter password');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final phone = _toPhone(emailOrPhone);

    try {
      // 0) Try unified auth first (super_admin / gym_admin)
      final authRes = await ApiClient.instance.post(
        '/auth/login',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'login_id': emailOrPhone.trim(), 'password': password}),
      );
      if (authRes.statusCode >= 200 && authRes.statusCode < 300) {
        final authData = jsonDecode(authRes.body) as Map<String, dynamic>;
        final role = authData['role'] as String?;
        final token = authData['token'] as String?;
        final loginId = authData['login_id'] as String? ?? emailOrPhone.trim();
        if (role == 'super_admin' && token != null && token.isNotEmpty) {
          await SecureStorage.setAuthToken(token);
          await SecureStorage.setAuthRole('super_admin');
          ApiClient.setAuthToken(token);
          if (!mounted) return;
          setState(() => _loading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SuperAdminScreen()),
          );
          return;
        }
        if (role == 'gym_admin' && token != null && token.isNotEmpty) {
          await SecureStorage.setAuthToken(token);
          await SecureStorage.setAuthRole('gym_admin');
          await SecureStorage.setAdminPhone(loginId);
          ApiClient.setAuthToken(token);
          if (!mounted) return;
          setState(() => _loading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
          );
          return;
        }
        if (role == 'member' && token != null && token.isNotEmpty) {
          await SecureStorage.setAuthToken(token);
          await SecureStorage.setAuthRole('member');
          ApiClient.setAuthToken(token);
          final memberMap = authData['member'] as Map<String, dynamic>?;
          if (!mounted) return;
          setState(() => _loading = false);
          if (memberMap != null) {
            final member = Member.fromJson(memberMap);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => MemberHomeScreen(member: member)),
            );
          } else {
            setState(() => _error = 'Member data missing');
          }
          return;
        }
      }

      if (authRes.statusCode == 403) {
        final body = jsonDecode(authRes.body) as Map<String, dynamic>?;
        final detail = body?['detail']?.toString() ?? 'Access denied';
        if (mounted) setState(() { _error = detail; _loading = false; });
        return;
      }

      // Try member by phone (no password) for member lookup
      final r = await ApiClient.instance.get(
        '/members/by-phone/${Uri.encodeComponent(phone)}',
        useCache: false,
      );

      if (!mounted) return;

      if (r.statusCode >= 200 && r.statusCode < 300) {
        final member = ApiClient.parseMember(r.body);
        setState(() => _loading = false);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MemberHomeScreen(member: member)),
        );
        return;
      }

      setState(() {
        _error = 'Invalid credentials or member not found';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        final msg = e.toString().split('\n').first;
        setState(() {
          _error = 'Could not sign in. $msg Use Back → Set server URL for local (e.g. http://127.0.0.1:8000).';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final outline = Theme.of(context).colorScheme.outline;
    final padding = LayoutConstants.screenPadding(context);
    final radius = LayoutConstants.cardRadius(context);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image (login screen only)
          Positioned.fill(
            child: Image.asset(
              loginBackgroundAsset,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: const Color(0xFFE3F2FD)),
            ),
          ),
          // Light overlay so form text stays readable
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.75),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: padding + 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (Navigator.of(context).canPop())
                    Tooltip(
                      message: 'Go back',
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                        label: const Text('Back'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade600,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  if (ThemeChangerScope.maybeOf(context) != null)
                    Builder(
                      builder: (context) {
                        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
                        return Tooltip(
                          message: isDarkMode ? 'Light mode' : 'Dark mode',
                          child: IconButton(
                            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
                            onPressed: () => ThemeChangerScope.maybeOf(context)!.setThemeDark(!isDarkMode),
                          ),
                        );
                      },
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 8),
              // Logo + App name row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo with ClipOval to crop to circle so white corners don't show
                  Container(
                    height: 120,
                    width: 120,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        defaultLogoAsset,
                        height: 100,
                        width: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 100,
                          width: 100,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.fitness_center, color: AppTheme.primary, size: 48),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        defaultGymName,
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'Welcome',
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to your gym dashboard',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 32),
              // Email or Mobile Number
              Text(
                'Email or Mobile Number',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailOrPhoneController,
                keyboardType: TextInputType.emailAddress,
                maxLength: _emailOrPhoneMaxLength,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.phone_android_outlined, size: 22),
                  filled: true,
                  fillColor: surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radius),
                    borderSide: BorderSide(color: outline.withOpacity(0.6)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  counterText: '',
                ),
                style: GoogleFonts.poppins(color: onSurface),
                onChanged: (String text) {
                  setState(() => _error = null);
                  final hasAt = text.contains('@');
                  final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(text);
                  if (hasAt || hasLetter) {
                    if (_emailOrPhoneMaxLength != 50) setState(() => _emailOrPhoneMaxLength = 50);
                    if (text.length > 50) {
                      _emailOrPhoneController.text = text.substring(0, 50);
                      _emailOrPhoneController.selection = TextSelection.collapsed(offset: 50);
                    }
                  } else {
                    if (_emailOrPhoneMaxLength != 10) setState(() => _emailOrPhoneMaxLength = 10);
                    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length > 10 || text != digits) {
                      final truncated = digits.length > 10 ? digits.substring(0, 10) : digits;
                      _emailOrPhoneController.text = truncated;
                      _emailOrPhoneController.selection = TextSelection.collapsed(offset: truncated.length);
                    }
                  }
                },
              ),
              const SizedBox(height: 20),
              // Password
              Text(
                'Password',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outline, size: 22),
                  suffixIcon: Tooltip(
                    message: _obscurePassword ? 'Show password' : 'Hide password',
                    child: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 22,
                        color: Colors.grey.shade600,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  filled: true,
                  fillColor: surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radius),
                    borderSide: BorderSide(color: outline.withOpacity(0.6)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: GoogleFonts.poppins(color: onSurface),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: 'Request password reset link',
                  child: TextButton(
                    onPressed: () => _showForgotPasswordDialog(context, padding, radius, onSurface, surface, outline),
                    child: Text(
                      'Forgot password?',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: AppTheme.error.withOpacity(0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 22, color: AppTheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.poppins(color: AppTheme.error, fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              Tooltip(
                message: 'Sign in with email or phone and password',
                child: FilledButton(
                  onPressed: _loading ? null : _signIn,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(radius),
                    ),
                  ),
                  child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.onPrimary,
                        ),
                      )
                    : Text(
                        'Sign In',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'New here?',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                  ),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SignUpScreen()),
                            );
                          },
                    child: Text(
                      'Sign up',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }
}
