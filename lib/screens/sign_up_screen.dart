import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static const String _recipientEmail = 'contact@dertzinfotech.com';
  static const String _contactUsUrl = String.fromEnvironment(
    'SIGNUP_PROXY_URL',
    defaultValue: '/api/contact-user-proxy',
  );

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _countryCodeController = TextEditingController(text: '+91');
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _countryCodeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String? _validateName(String? value, String label) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$label is required';
    if (v.length < 2) return '$label must be at least 2 characters';
    return null;
  }

  String? _validateCountryCode(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Country extension is required';
    if (!RegExp(r'^\+[0-9]{1,4}$').hasMatch(v)) {
      return 'Use format like +91';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Phone number is required';
    if (digits.length != 10) {
      return 'Phone number must be exactly 10 digits';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required';
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
    if (!valid) return 'Enter a valid email';
    return null;
  }

  Future<void> _submit() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final countryCode = _countryCodeController.text.trim();
    final phoneDigits = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final userEmail = _emailController.text.trim();
    final fullName = '$firstName $lastName'.trim();
    final contact = '${countryCode.replaceAll('+', '')}$phoneDigits';
    final hiddenMessage = 'GymOpsHQ | UserEmail: $userEmail | UserPhone: $contact';

    setState(() => _submitting = true);
    try {
      final response = await http
          .post(
            Uri.parse(_contactUsUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': fullName,
              'email': _recipientEmail,
              'contact': contact,
              'company': 'NA',
              'message': hiddenMessage,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign up submitted successfully')),
        );
        Navigator.of(context).pop();
      } else {
        String detail = 'Could not submit sign up. Please try again.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic> && body['detail'] != null) {
            detail = body['detail'].toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
      }
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final lower = raw.toLowerCase();
      final isFetchFailure = lower.contains('failed to fetch') || lower.contains('clientexception');
      final message = isFetchFailure
          ? 'Signup request failed. Please try again in a moment or contact support.'
          : 'Request failed: ${raw.split('\n').first}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final radius = 14.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Text(
          'Sign Up',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onSurface),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create your account request',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Fill in your details. We will contact you shortly.',
                      style: GoogleFonts.poppins(fontSize: 14, color: onSurface.withOpacity(0.7)),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _firstNameController,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration('First Name'),
                            validator: (v) => _validateName(v, 'First name'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _lastNameController,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration('Last Name'),
                            validator: (v) => _validateName(v, 'Last name'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _countryCodeController,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.phone,
                            decoration: _inputDecoration('Code'),
                            validator: _validateCountryCode,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 4,
                          child: TextFormField(
                            controller: _phoneController,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.phone,
                            inputFormatters: const [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            decoration: _inputDecoration('Phone Number'),
                            validator: _validatePhone,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _emailController,
                      textInputAction: TextInputAction.done,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _inputDecoration('Email ID'),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: AppTheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.onPrimary,
                              ),
                            )
                          : Text(
                              'Submit',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFFCFCFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}
