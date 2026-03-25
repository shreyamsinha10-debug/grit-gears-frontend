// ---------------------------------------------------------------------------
// Admin login – phone + OTP; stores admin phone/PIN in secure storage.
// ---------------------------------------------------------------------------
// Used when app is configured to show separate admin vs member login.
// On success navigates to [AdminDashboardScreen].
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/secure_storage.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard_screen.dart';


class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _loading = false;
  bool _otpSent = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter phone number');
      return;
    }
    setState(() { _loading = true; _error = null; });
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() { _otpSent = true; _loading = false; });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OTP sent (simulated). Use 123456 to login.')),
    );
  }

  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    final _ = _otpController.text.trim(); // OTP validated by backend when implemented
    if (phone.isEmpty) {
      setState(() => _error = 'Enter phone number');
      return;
    }
    setState(() { _loading = true; _error = null; });
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final savedAdmin = await SecureStorage.getAdminPhone();

    if (savedAdmin != null && savedAdmin != phone) {
      setState(() {
        _error = 'This phone is not authorized as admin. Use the owner phone.';
        _loading = false;
      });
      return;
    }

    if (savedAdmin == null) {
      await SecureStorage.setAdminPhone(phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Owner phone saved. You have full admin access.')),
        );
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Admin Login', style: GoogleFonts.poppins(color: AppTheme.onSurface, fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.onSurface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(LayoutConstants.screenPadding(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Gym owner access',
                style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the phone number you will use as the gym owner. The first successful login authorizes this phone for full admin access.',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => _error = null),
              ),
              if (!_otpSent) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _requestOtp,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                      : const Text('Send OTP'),
                ),
              ] else ...[
                const SizedBox(height: 20),
                TextField(
                  controller: _otpController,
                  decoration: const InputDecoration(
                    labelText: 'OTP',
                    border: OutlineInputBorder(),
                    hintText: '123456',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _loading ? null : _login,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                      : const Text('Login as Admin'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
