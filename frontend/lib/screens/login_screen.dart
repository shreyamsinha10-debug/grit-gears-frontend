// ---------------------------------------------------------------------------
// Login – unified entry: phone/email + password, routes to Admin or Member.
// ---------------------------------------------------------------------------
// Calls backend to validate; admin (default 9999999999/999999) goes to
// Admin Dashboard, member (by phone) goes to Member Home. Handles server
// URL config and theme toggle. See [LoginScreen].
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/secure_storage.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard_screen.dart';
import 'member_home_screen.dart';
import 'super_admin_screen.dart';

/// Single login screen: Email or Mobile + Password. Routes to Admin or Member based on credentials.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Default admin: phone 9999999999, OTP/password 999999
const String _defaultAdminPhone = '9999999999';
const String _defaultAdminOtp = '999999';

class _LoginScreenState extends State<LoginScreen> {
  final _emailOrPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  int _emailOrPhoneMaxLength = 10;  // 10 for phone, 50 for email

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
                            'If an account exists for that email or phone number, you’ll receive instructions to reset your password shortly.',
                            style: GoogleFonts.poppins(fontSize: 14, color: onSurface),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enter your email or mobile number and we’ll send you a link to reset your password.',
                            style: GoogleFonts.poppins(fontSize: 14, color: onSurface),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: controller,
                            keyboardType: TextInputType.emailAddress,
                            maxLength: 50,
                            decoration: InputDecoration(
                              labelText: 'Email or Mobile Number',
                              hintText: 'e.g. 8447594017 or email@example.com',
                              prefixIcon: const Icon(Icons.phone_android_outlined, size: 22),
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
                                const SnackBar(content: Text('Enter email or mobile number')),
                              );
                              return;
                            }
                            loading = true;
                            setDialogState(() {});
                            await Future.delayed(const Duration(milliseconds: 800));
                            if (!ctx.mounted) return;
                            loading = false;
                            sent = true;
                            setDialogState(() {});
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
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => MemberHomeScreen(member: memberMap)),
            );
          } else {
            setState(() => _error = 'Member data missing');
          }
          return;
        }
      }

      // 1) Default admin: 9999999999 / 999999 – use auth API to get token (with gym_id) so dashboard calls are scoped
      if (phone == _defaultAdminPhone && password == _defaultAdminOtp) {
        final authRes = await ApiClient.instance.post(
          '/auth/login',
          body: jsonEncode({'login_id': _defaultAdminPhone, 'password': password}),
          headers: {'Content-Type': 'application/json'},
        );
        if (authRes.statusCode >= 200 && authRes.statusCode < 300) {
          final authData = jsonDecode(authRes.body) as Map<String, dynamic>?;
          final tok = authData?['token'] as String?;
          if (tok != null && tok.isNotEmpty) {
            await SecureStorage.setAuthToken(tok);
            await SecureStorage.setAuthRole('gym_admin');
            await SecureStorage.setAdminPhone(_defaultAdminPhone);
            ApiClient.setAuthToken(tok);
          }
        }
        if (!mounted) return;
        setState(() => _loading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
        return;
      }

      final savedAdmin = await SecureStorage.getAdminPhone();

      // 1) If this credential matches saved admin → Admin dashboard
      if (savedAdmin != null && (savedAdmin == phone || savedAdmin == emailOrPhone)) {
        if (!mounted) return;
        setState(() => _loading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
        return;
      }

      // 2) Try member by phone (for both: existing member, or when no admin saved yet)
      final r = await ApiClient.instance.get(
        '/members/by-phone/${Uri.encodeComponent(phone)}',
        useCache: false,
      );

      if (!mounted) return;

      if (r.statusCode >= 200 && r.statusCode < 300) {
        final member = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _loading = false);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MemberHomeScreen(member: member)),
        );
        return;
      }

      // 3) Not a member: if no admin saved yet, first login becomes admin (owner)
      if (savedAdmin == null) {
        await SecureStorage.setAdminPhone(phone);
        if (mounted) {
          setState(() => _loading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Welcome. You have full admin access.')),
          );
        }
        return;
      }

      setState(() {
        _error = 'Invalid credentials or member not found';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not sign in. Check connection.';
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
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  label: const Text('Back'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Logo + App name row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      defaultLogoAsset,
                      height: 56,
                      width: 56,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        height: 56,
                        width: 56,
                        color: AppTheme.primary.withOpacity(0.2),
                        child: const Icon(Icons.fitness_center, color: AppTheme.primary, size: 32),
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
                  hintText: 'e.g. 8447594017 or email@example.com',
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
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 22,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
              if (_error != null) ...[
                Text(
                  _error!,
                  style: GoogleFonts.poppins(color: AppTheme.error, fontSize: 13),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              FilledButton(
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
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }
}
