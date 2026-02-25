// ---------------------------------------------------------------------------
// Member login – phone + OTP; on success navigates to Member Home.
// ---------------------------------------------------------------------------
// Backend validates OTP (or simulated flow). Member is identified by phone
// for subsequent API calls (attendance, payments, etc.).
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../theme/app_theme.dart';
import 'member_home_screen.dart';

const _padding = 20.0;

class MemberLoginScreen extends StatefulWidget {
  const MemberLoginScreen({super.key});

  @override
  State<MemberLoginScreen> createState() => _MemberLoginScreenState();
}

class _MemberLoginScreenState extends State<MemberLoginScreen> {
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
    await Future.delayed(const Duration(milliseconds: 800));
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
    try {
      final r = await ApiClient.instance.get('/members/by-phone/${Uri.encodeComponent(phone)}', useCache: false);
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final member = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _loading = false);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MemberHomeScreen(member: member)),
        );
      } else {
        setState(() { _error = 'Member not found or invalid phone'; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().split('\n').first; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('Member Login', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(_padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Image.asset(
                  defaultLogoAsset,
                  height: 72,
                  width: 72,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.fitness_center, color: AppTheme.primary, size: 36),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Are you a Gym Member? Login here',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in with your registered phone',
                style: GoogleFonts.poppins(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Phone',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.phone),
                  filled: true,
                  fillColor: AppTheme.surfaceVariant.withOpacity(0.5),
                ),
                style: GoogleFonts.poppins(color: AppTheme.onSurface),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (!_otpSent) ...[
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(_error!, style: GoogleFonts.poppins(color: Colors.red, fontSize: 13)),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _loading ? null : _requestOtp,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                      : const Text('Send OTP'),
                ),
              ] else ...[
                const SizedBox(height: 20),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'OTP',
                    hintText: '123456',
                    border: OutlineInputBorder(),
                  ),
                  style: GoogleFonts.poppins(color: AppTheme.onSurface),
                  onChanged: (_) => setState(() => _error = null),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: GoogleFonts.poppins(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _login,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                      : const Text('Login'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
