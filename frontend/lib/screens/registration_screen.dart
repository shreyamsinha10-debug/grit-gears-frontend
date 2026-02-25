// ---------------------------------------------------------------------------
// Registration – new member sign-up: form, photo, ID document, POST /members.
// ---------------------------------------------------------------------------
// Admin-only. Collects name, phone, email, membership type, batch, optional
// workout schedule, diet chart, photo (base64), ID document (base64). On submit
// calls backend /members and shows success or error.
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../theme/app_theme.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();

  String _membershipType = 'Regular';
  String _batch = 'Morning';
  DateTime? _dateOfBirth;
  bool _isSubmitting = false;

  /// Member photo (JPEG/PNG) as base64; null if not set.
  String? _photoBase64;
  /// ID document (PDF or image) as base64; null if not set.
  String? _idDocumentBase64;
  /// Type of ID: Aadhar, Driving Licence, Voter ID, Passport.
  String _idDocumentType = 'Aadhar';

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      setState(() => _photoBase64 = base64Encode(bytes));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick photo: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<void> _pickIdDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      List<int>? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (_) {}
      }
      if (bytes == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read file')));
        return;
      }
      setState(() => _idDocumentBase64 = base64Encode(bytes!));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick document: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final body = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'membership_type': _membershipType,
        'batch': _batch,
        'status': 'Active',
      };
      final address = _addressController.text.trim();
      if (address.isNotEmpty) body['address'] = address;
      if (_dateOfBirth != null) body['date_of_birth'] = formatApiDate(_dateOfBirth!);
      if (_photoBase64 != null) body['photo_base64'] = _photoBase64;
      if (_idDocumentBase64 != null) {
        body['id_document_base64'] = _idDocumentBase64;
        body['id_document_type'] = _idDocumentType;
      }

      final response = await ApiClient.instance.post(
        '/members',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _formKey.currentState!.reset();
        _nameController.clear();
        _phoneController.clear();
        _emailController.clear();
        setState(() {
          _membershipType = 'Regular';
          _batch = 'Morning';
          _dateOfBirth = null;
          _addressController.clear();
          _photoBase64 = null;
          _idDocumentBase64 = null;
          _idDocumentType = 'Aadhar';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.surface, size: 22),
                SizedBox(width: 12),
                Expanded(child: Text('Member registered successfully!')),
              ],
            ),
          ),
        );
      } else {
        final body = response.body;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: AppTheme.surface, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text('Error: ${body.length > 80 ? '${body.substring(0, 80)}...' : body}')),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: AppTheme.surface, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text('Failed to register: ${e.toString().split('\n').first}')),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
        title: Text(
          'Register Member',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.onSurface,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: LayoutConstants.screenPadding(context), vertical: 8),
          children: [
            _buildSection(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: _inputDecoration('Name', 'Full name'),
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Name is required';
                      return null;
                    },
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'^\s'))],
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _phoneController,
                    decoration: _inputDecoration('Phone', 'Phone number'),
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Phone is required';
                      if (v.length != 10) return 'Enter 10-digit phone number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emailController,
                    decoration: _inputDecoration('Email', 'email@example.com'),
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required';
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v.trim())) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _addressController,
                    decoration: _inputDecoration('Address (optional)', 'Street, city, PIN'),
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dateOfBirth ?? DateTime(2000),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null && mounted) setState(() => _dateOfBirth = picked);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: _inputDecoration('Date of birth (optional)', null),
                      child: Text(
                        _dateOfBirth != null ? formatDisplayDate(_dateOfBirth) : 'Select date of birth',
                        style: GoogleFonts.poppins(
                          color: _dateOfBirth != null ? AppTheme.onSurface : Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _membershipType,
                    decoration: _inputDecoration('Membership Type', null),
                    dropdownColor: AppTheme.surfaceVariant,
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    items: [
                      DropdownMenuItem(value: 'Regular', child: Text('Regular', style: GoogleFonts.poppins(color: AppTheme.onSurface))),
                      DropdownMenuItem(value: 'PT', child: Text('PT', style: GoogleFonts.poppins(color: AppTheme.onSurface))),
                    ],
                    onChanged: (v) => setState(() => _membershipType = v ?? 'Regular'),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _batch,
                    decoration: _inputDecoration('Batch', null),
                    dropdownColor: AppTheme.surfaceVariant,
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    items: [
                      DropdownMenuItem(value: 'Morning', child: Text('Morning', style: GoogleFonts.poppins(color: AppTheme.onSurface))),
                      DropdownMenuItem(value: 'Evening', child: Text('Evening', style: GoogleFonts.poppins(color: AppTheme.onSurface))),
                      DropdownMenuItem(value: 'Ladies', child: Text('Ladies', style: GoogleFonts.poppins(color: AppTheme.onSurface))),
                    ],
                    onChanged: (v) => setState(() => _batch = v ?? 'Morning'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Upload photo',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _UploadCard(
                    label: 'Upload photo',
                    icon: Icons.add_a_photo_rounded,
                    hasFile: _photoBase64 != null,
                    onTap: _pickPhoto,
                    imageBase64: _photoBase64,
                    onClear: () => setState(() => _photoBase64 = null),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Upload ID',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _idDocumentType,
                    decoration: _inputDecoration('ID document type', null),
                    dropdownColor: AppTheme.surfaceVariant,
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    items: const [
                      DropdownMenuItem(value: 'Aadhar', child: Text('Aadhar')),
                      DropdownMenuItem(value: 'Driving Licence', child: Text('Driving Licence')),
                      DropdownMenuItem(value: 'Voter ID', child: Text('Voter ID')),
                      DropdownMenuItem(value: 'Passport', child: Text('Passport')),
                    ],
                    onChanged: (v) => setState(() => _idDocumentType = v ?? 'Aadhar'),
                  ),
                  const SizedBox(height: 12),
                  _UploadCard(
                    label: 'Upload ID document',
                    icon: Icons.badge_rounded,
                    hasFile: _idDocumentBase64 != null,
                    onTap: _pickIdDocument,
                    imageBase64: null,
                    isDocument: true,
                    onClear: () => setState(() => _idDocumentBase64 = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary),
                    )
                  : const Icon(Icons.person_add_rounded),
              label: Text(_isSubmitting ? 'Saving...' : 'Register Member'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: AppTheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String? hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.poppins(color: AppTheme.primary),
      hintStyle: GoogleFonts.poppins(color: Colors.grey),
      filled: true,
      fillColor: AppTheme.surfaceVariant.withOpacity(0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required Widget child}) {
    final padding = LayoutConstants.screenPadding(context);
    final radius = LayoutConstants.cardRadius(context);
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(radius + 4),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}

class _UploadCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool hasFile;
  final VoidCallback onTap;
  final String? imageBase64;
  final bool isDocument;
  final VoidCallback onClear;

  const _UploadCard({
    required this.label,
    required this.icon,
    required this.hasFile,
    required this.onTap,
    this.imageBase64,
    this.isDocument = false,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              if (imageBase64 != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(imageBase64!),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: AppTheme.primary.withOpacity(0.2),
                      child: Icon(icon, color: AppTheme.primary, size: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ] else if (hasFile && isDocument)
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.description_rounded, color: AppTheme.primary, size: 28),
                ),
              if (hasFile && (imageBase64 != null || isDocument)) const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasFile ? 'File added' : label,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                        fontSize: 15,
                      ),
                    ),
                    if (!hasFile)
                      Text(
                        'Tap to select',
                        style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
                      ),
                  ],
                ),
              ),
              if (hasFile)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onClear,
                  tooltip: 'Remove',
                )
              else
                Icon(icon, color: AppTheme.primary.withOpacity(0.8), size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
