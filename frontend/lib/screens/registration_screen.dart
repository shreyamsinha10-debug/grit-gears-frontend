// ---------------------------------------------------------------------------
// Registration – new member sign-up: form, photo, ID document, POST /members.
// ---------------------------------------------------------------------------
// Admin-only. Collects name, phone, email, membership type, batch, optional
// workout schedule, diet chart, photo (base64), ID document (base64). On submit
// calls backend /members and shows success or error.
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../core/image_compression.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

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
  /// When user selects a membership plan from gym settings, this is the plan id; otherwise null (legacy Regular/PT).
  String? _selectedPlanId;
  String _batch = 'Morning';
  List<Map<String, dynamic>> _plans = [];
  /// Batches from gym profile: { name, start_time?, end_time? }. Used for Batch dropdown when non-empty.
  List<Map<String, dynamic>> _batches = [];

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  String? _gender;
  DateTime? _dateOfBirth;
  bool _isSubmitting = false;

  /// Member photo (JPEG/PNG) as base64; null if not set.
  String? _photoBase64;
  /// ID document (PDF or image) as base64; null if not set.
  String? _idDocumentBase64;
  /// Type of ID: Aadhar, Driving Licence, Voter ID, Passport.
  String _idDocumentType = 'Aadhar';

  Future<void> _loadPlans() async {
    try {
      final r = await ApiClient.instance.get('/gym/profile', useCache: true);
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final list = data['plans'] as List<dynamic>? ?? [];
        final batchList = data['batches'] as List<dynamic>? ?? [];
        setState(() {
          _plans = list.map((p) {
            final m = p as Map<String, dynamic>;
            return <String, dynamic>{
              'id': m['id'] as String?,
              'name': m['name'] as String?,
              'price': (m['price'] as num?)?.toInt() ?? 0,
              'duration_type': m['duration_type'] as String?,
              'is_active': m['is_active'] != false,
            };
          }).where((p) => p['is_active'] == true).toList();
          _batches = batchList.map((b) {
            final m = b as Map<String, dynamic>;
            final name = (m['name'] as String? ?? '').trim();
            if (name.isEmpty) return null;
            return <String, dynamic>{
              'name': name,
              'start_time': m['start_time'] as String?,
              'end_time': m['end_time'] as String?,
            };
          }).whereType<Map<String, dynamic>>().toList();
          // If current _batch is not in the new list, reset to first available (or Morning if empty)
          if (_batches.isNotEmpty && !_batches.any((b) => b['name'] == _batch)) {
            _batch = _batches.first['name'] as String;
          } else if (_batches.isEmpty) {
            _batch = 'Morning'; // Fallback if no batches exist
          }
        });
      } else {
        setState(() {});
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  /// Format "06:00" / "18:00" to "6:00 am" / "6:00 pm" for display.
  static String _formatTimeDisplay(String? time) {
    if (time == null || time.isEmpty) return '';
    final parts = time.split(':');
    if (parts.isEmpty) return time;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    if (h == 0 && m == 0) return '12:00 am';
    if (h == 12) return '12:${m.toString().padLeft(2, '0')} pm';
    if (h < 12) return '$h:${m.toString().padLeft(2, '0')} am';
    return '${h - 12}:${m.toString().padLeft(2, '0')} pm';
  }

  String _durationLabel(String? type) {
    const map = {'1m': 'month', '2m': '2mo', '3m': '3mo', '6m': '6mo', '1yr': 'year', 'one_time': 'one time'};
    return map[type] ?? type ?? '';
  }

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
      Uint8List bytes = await file.readAsBytes();
      if (bytes.length > kMaxImageBytes) bytes = compressImageToMaxBytes(bytes);
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
      if (bytes == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read file')));
        return;
      }
      final bytesList = Uint8List.fromList(bytes);
      final toEncode = isCompressibleImage(bytesList) ? compressImageToMaxBytes(bytesList) : bytesList;
      setState(() => _idDocumentBase64 = base64Encode(toEncode));
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
      if (_selectedPlanId != null && _selectedPlanId!.isNotEmpty) body['plan_id'] = _selectedPlanId;
      final address = _addressController.text.trim();
      if (address.isNotEmpty) body['address'] = address;
      if (_dateOfBirth != null) body['date_of_birth'] = formatApiDate(_dateOfBirth!);
      if (_gender != null && _gender!.isNotEmpty) body['gender'] = _gender;
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
          _selectedPlanId = null;
          _batch = _batches.isNotEmpty ? (_batches.first['name'] as String) : 'Morning';
          _dateOfBirth = null;
          _addressController.clear();
          _gender = null;
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
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => LoginScreen.logout(context),
          ),
        ],
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
                    value: _gender,
                    decoration: _inputDecoration('Gender (optional)', null),
                    dropdownColor: AppTheme.surfaceVariant,
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Select gender')),
                      const DropdownMenuItem(value: 'Male', child: Text('Male')),
                      const DropdownMenuItem(value: 'Female', child: Text('Female')),
                      const DropdownMenuItem(value: 'Other', child: Text('Other')),
                      const DropdownMenuItem(value: 'Prefer not to say', child: Text('Prefer not to say')),
                    ],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _membershipType,
                    decoration: _inputDecoration('Training type', null),
                    dropdownColor: AppTheme.surfaceVariant,
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    items: const [
                      DropdownMenuItem(value: 'Regular', child: Text('Regular')),
                      DropdownMenuItem(value: 'PT', child: Text('PT (Personal Training)')),
                    ],
                    onChanged: (v) => setState(() => _membershipType = v ?? 'Regular'),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _selectedPlanId,
                    decoration: _inputDecoration('Membership plan (optional)', null),
                    dropdownColor: AppTheme.surfaceVariant,
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('No plan — use Training type for billing')),
                      ..._plans.map((p) {
                        final id = p['id'] as String? ?? '';
                        final name = p['name'] as String? ?? '';
                        final price = p['price'] as int? ?? 0;
                        final dur = _durationLabel(p['duration_type'] as String?);
                        return DropdownMenuItem(
                          value: id,
                          child: Text('$name - ₹$price/$dur', style: GoogleFonts.poppins(color: AppTheme.onSurface)),
                        );
                      }),
                    ],
                    onChanged: (v) => setState(() => _selectedPlanId = v),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _batches.isEmpty
                        ? _batch
                        : (_batches.any((b) => b['name'] == _batch) ? _batch : _batches.first['name'] as String),
                    decoration: _inputDecoration('Batch', null),
                    dropdownColor: AppTheme.surfaceVariant,
                    style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 16),
                    items: _batches.isEmpty
                        ? [
                            DropdownMenuItem(value: 'Morning', child: Text('Morning', style: GoogleFonts.poppins(color: AppTheme.onSurface))),
                            DropdownMenuItem(value: 'Evening', child: Text('Evening', style: GoogleFonts.poppins(color: AppTheme.onSurface))),
                            DropdownMenuItem(value: 'Ladies', child: Text('Ladies', style: GoogleFonts.poppins(color: AppTheme.onSurface))),
                          ]
                        : _batches.map((b) {
                            final name = b['name'] as String;
                            final st = _formatTimeDisplay(b['start_time'] as String?);
                            final et = _formatTimeDisplay(b['end_time'] as String?);
                            final label = st.isEmpty && et.isEmpty ? name : '$name ${st.isEmpty ? '' : st}${st.isEmpty || et.isEmpty ? '' : ' – '}$et';
                            return DropdownMenuItem(value: name, child: Text(label, style: GoogleFonts.poppins(color: AppTheme.onSurface)));
                          }).toList(),
                    onChanged: (v) => setState(() => _batch = v ?? (_batches.isNotEmpty ? _batches.first['name'] as String : 'Morning')),
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
