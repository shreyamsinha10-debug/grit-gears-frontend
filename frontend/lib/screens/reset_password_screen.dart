// ---------------------------------------------------------------------------
// Reset password screen – opened when user follows the link from forgot-password email.
// Token is passed in (from URL query or deep link). Calls POST /auth/reset-password.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.instance.post(
        '/auth/reset-password',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': widget.token,
          'new_password': password,
        }),
      );
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        final message = data?['message']?.toString() ?? 'Password updated. You can now sign in.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>?;
        final detail = body?['detail']?.toString() ?? 'Failed to update password';
        setState(() { _loading = false; _error = detail; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error: ${e.toString().split('\n').first}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final outline = Theme.of(context).colorScheme.outline;
    final padding = LayoutConstants.screenPadding(context);
    final radius = LayoutConstants.cardRadius(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: padding + 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                label: const Text('Back'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),
              Icon(Icons.lock_reset, color: AppTheme.primary, size: 56),
              const SizedBox(height: 16),
              Text(
                'Set new password',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter a new password for your account.',
                style: GoogleFonts.poppins(fontSize: 14, color: onSurface.withOpacity(0.8)),
              ),
              const SizedBox(height: 28),
              Text(
                'New password',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: onSurface),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'At least 6 characters',
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radius),
                    borderSide: BorderSide(color: outline.withOpacity(0.6)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: GoogleFonts.poppins(color: onSurface),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 20),
              Text(
                'Confirm password',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: onSurface),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  hintText: 'Re-enter password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 22),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 22,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  filled: true,
                  fillColor: surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radius),
                    borderSide: BorderSide(color: outline.withOpacity(0.6)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: GoogleFonts.poppins(color: onSurface),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: AppTheme.error.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 22, color: AppTheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.poppins(color: AppTheme.error, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary),
                      )
                    : Text(
                        'Update password',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
