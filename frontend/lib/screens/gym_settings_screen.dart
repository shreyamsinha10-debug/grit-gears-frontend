// Gym settings – gym_admin: gym name, logo, invoice name.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../theme/app_theme.dart';

class GymSettingsScreen extends StatefulWidget {
  const GymSettingsScreen({super.key});

  @override
  State<GymSettingsScreen> createState() => _GymSettingsScreenState();
}

class _GymSettingsScreenState extends State<GymSettingsScreen> {
  final _nameController = TextEditingController();
  final _invoiceNameController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _logoBase64;
  bool _logoChanged = false;
  bool _pickingImage = false;

  static final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickLogo() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (!mounted) return;
      if (file != null) {
        final bytes = await file.readAsBytes();
        final base64 = base64Encode(bytes);
        setState(() {
          _logoBase64 = base64;
          _logoChanged = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: ${e.toString()}')),
        );
      }
    }
    if (mounted) setState(() => _pickingImage = false);
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _invoiceNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ApiClient.instance.get('/gym/profile', useCache: false);
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        _nameController.text = (data['name'] as String?) ?? '';
        _invoiceNameController.text = (data['invoice_name'] as String?) ?? '';
        _logoBase64 = data['logo_base64'] as String?;
        _logoChanged = false;
      } else {
        _error = 'Failed to load gym profile';
      }
    } catch (e) {
      if (mounted) _error = 'Could not load profile. Check connection.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Gym name is required');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final body = <String, dynamic>{
        'name': name,
        'invoice_name': _invoiceNameController.text.trim().isEmpty ? null : _invoiceNameController.text.trim(),
      };
      if (_logoChanged) body['logo_base64'] = _logoBase64?.isNotEmpty == true ? _logoBase64 : null;
      final r = await ApiClient.instance.patch(
        '/gym/profile',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gym settings saved')));
        Navigator.pop(context, true);
      } else {
        final msg = (jsonDecode(r.body) as Map<String, dynamic>?)?['detail'] ?? 'Failed to save';
        setState(() => _error = msg is String ? msg : 'Failed to save');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save. Check connection.');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.of(context).padding;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gym settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Gym settings', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, padding.bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: GoogleFonts.poppins(color: theme.colorScheme.onErrorContainer)),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text('Gym name', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'e.g. Jupiter Arena',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              ),
              style: GoogleFonts.poppins(),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),
            Text('Name on invoices', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
            const SizedBox(height: 6),
            TextField(
              controller: _invoiceNameController,
              decoration: InputDecoration(
                hintText: 'Same as gym name if left blank',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              ),
              style: GoogleFonts.poppins(),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),
            Text('Logo', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
            const SizedBox(height: 8),
            if (_logoBase64 != null && _logoBase64!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(_logoBase64!),
                      height: 100,
                      width: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(height: 100, width: 100, child: Icon(Icons.broken_image)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _pickingImage ? null : _pickLogo,
                        icon: _pickingImage ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.image, size: 18),
                        label: Text(_pickingImage ? 'Picking...' : 'Change logo'),
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () => setState(() { _logoBase64 = null; _logoChanged = true; }),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove logo'),
                      ),
                    ],
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'No logo set. Upload an image from your device.',
                    style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _pickingImage ? null : _pickLogo,
                    icon: _pickingImage ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload),
                    label: Text(_pickingImage ? 'Picking image...' : 'Upload logo'),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ],
              ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(_saving ? 'Saving...' : 'Save changes', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
