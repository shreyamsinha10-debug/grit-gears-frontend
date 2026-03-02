// Gym settings – gym_admin: gym name, logo, invoice name.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/image_compression.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class GymSettingsScreen extends StatefulWidget {
  /// When true, only the form body is shown (no AppBar); use for embedding in dashboard Settings tab.
  final bool embedded;
  /// Called after successful save when [embedded] is true (instead of popping).
  final VoidCallback? onSaved;

  const GymSettingsScreen({super.key, this.embedded = false, this.onSaved});

  @override
  State<GymSettingsScreen> createState() => _GymSettingsScreenState();
}

class _GymSettingsScreenState extends State<GymSettingsScreen> {
  final _nameController = TextEditingController();
  final _invoiceNameController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pinCodeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _termsController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _logoBase64;
  bool _logoChanged = false;
  bool _pickingImage = false;
  /// Batches: list of { id, name, description, start_time, end_time }; id may be empty for new.
  List<Map<String, String>> _batches = [];
  /// Membership plans: id, name, description, price, duration_type, is_active, registration_fee, waive_registration_fee
  List<Map<String, dynamic>> _plans = [];

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
        Uint8List bytes = await file.readAsBytes();
        if (bytes.length > kMaxImageBytes) bytes = compressImageToMaxBytes(bytes);
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
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pinCodeController.dispose();
    _phoneController.dispose();
    _termsController.dispose();
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
        _addressLine1Controller.text = (data['address_line1'] as String?) ?? '';
        _addressLine2Controller.text = (data['address_line2'] as String?) ?? '';
        _cityController.text = (data['city'] as String?) ?? '';
        _stateController.text = (data['state'] as String?) ?? '';
        _pinCodeController.text = (data['pin_code'] as String?) ?? '';
        _phoneController.text = (data['phone'] as String?) ?? '';
        _termsController.text = (data['terms_and_conditions'] as String?) ?? '';
        final batchesList = data['batches'] as List<dynamic>? ?? [];
        _batches = batchesList.map((b) {
          final m = b as Map<String, dynamic>;
          return <String, String>{
            'id': (m['id'] as String?) ?? '',
            'name': (m['name'] as String?) ?? '',
            'description': (m['description'] as String?) ?? '',
            'start_time': (m['start_time'] as String?) ?? '',
            'end_time': (m['end_time'] as String?) ?? '',
          };
        }).toList();
        final plansList = data['plans'] as List<dynamic>? ?? [];
        _plans = plansList.map((p) {
          final m = p as Map<String, dynamic>;
          return <String, dynamic>{
            'id': (m['id'] as String?) ?? '',
            'name': (m['name'] as String?) ?? '',
            'description': (m['description'] as String?) ?? '',
            'price': (m['price'] as num?)?.toInt() ?? 0,
            'duration_type': (m['duration_type'] as String?) ?? '1m',
            'is_active': m['is_active'] != false,
            'registration_fee': (m['registration_fee'] as num?)?.toInt(),
            'waive_registration_fee': m['waive_registration_fee'] == true,
          };
        }).toList();
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
        'address_line1': _addressLine1Controller.text.trim().isEmpty ? null : _addressLine1Controller.text.trim(),
        'address_line2': _addressLine2Controller.text.trim().isEmpty ? null : _addressLine2Controller.text.trim(),
        'city': _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        'state': _stateController.text.trim().isEmpty ? null : _stateController.text.trim(),
        'pin_code': _pinCodeController.text.trim().isEmpty ? null : _pinCodeController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'terms_and_conditions': _termsController.text.trim().isEmpty ? null : _termsController.text.trim(),
        'batches': _batches.map((b) => {
          'id': b['id'],
          'name': b['name']!,
          'description': (b['description'] ?? '').trim().isEmpty ? null : (b['description'] ?? '').trim(),
          'start_time': (b['start_time'] ?? '').trim().isEmpty ? null : (b['start_time'] ?? '').trim(),
          'end_time': (b['end_time'] ?? '').trim().isEmpty ? null : (b['end_time'] ?? '').trim(),
        }).toList(),
        'plans': _plans.map((p) => {
          'id': p['id'],
          'name': p['name'] as String,
          'description': (p['description'] as String? ?? '').trim().isEmpty ? null : (p['description'] as String?)!.trim(),
          'price': p['price'] as int,
          'duration_type': p['duration_type'] as String,
          'is_active': p['is_active'] as bool,
          'registration_fee': p['registration_fee'] as int?,
          'waive_registration_fee': p['waive_registration_fee'] as bool,
        }).toList(),
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
        if (widget.embedded) {
          widget.onSaved?.call();
        } else {
          Navigator.pop(context, true);
        }
      } else {
        final msg = (jsonDecode(r.body) as Map<String, dynamic>?)?['detail'] ?? 'Failed to save';
        setState(() => _error = msg is String ? msg : 'Failed to save');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save. Check connection.');
    }
    if (mounted) setState(() => _saving = false);
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

  static String _timeOfDayToStr(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Add [minutes] to [t]; wraps around midnight (24h).
  static TimeOfDay _timeOfDayAddMinutes(TimeOfDay t, int minutes) {
    int totalM = t.hour * 60 + t.minute + minutes;
    totalM = totalM % (24 * 60);
    if (totalM < 0) totalM += 24 * 60;
    return TimeOfDay(hour: totalM ~/ 60, minute: totalM % 60);
  }

  /// Show time picker in 12-hour AM/PM format.
  Future<TimeOfDay?> _showTimePickerAmPm(BuildContext context, TimeOfDay initialTime) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );
  }

  /// Duration presets for batch: label -> minutes.
  static const List<MapEntry<String, int>> _batchDurationPresets = [
    MapEntry('30 min', 30),
    MapEntry('1 hr', 60),
    MapEntry('1.5 hr', 90),
    MapEntry('2 hr', 120),
    MapEntry('2.5 hr', 150),
    MapEntry('3 hr', 180),
  ];

  void _showCreateBatchDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    TimeOfDay startTime = const TimeOfDay(hour: 6, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 8, minute: 0);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Create batch', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Batch name', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Ladies/Morning, Gents/Evening',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                  ),
                  style: GoogleFonts.poppins(),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Text('Batch timings', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(_formatTimeDisplay(_timeOfDayToStr(startTime)), style: GoogleFonts.poppins()),
                        onPressed: () async {
                          final picked = await _showTimePickerAmPm(context, startTime);
                          if (picked != null) setDialogState(() => startTime = picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('to', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(_formatTimeDisplay(_timeOfDayToStr(endTime)), style: GoogleFonts.poppins()),
                        onPressed: () async {
                          final picked = await _showTimePickerAmPm(context, endTime);
                          if (picked != null) setDialogState(() => endTime = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Duration from start', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _batchDurationPresets.map((e) {
                    final end = _timeOfDayAddMinutes(startTime, e.value);
                    final selected = endTime.hour == end.hour && endTime.minute == end.minute;
                    return ChoiceChip(
                      label: Text(e.key, style: GoogleFonts.poppins(fontSize: 12)),
                      selected: selected,
                      onSelected: (_) => setDialogState(() => endTime = end),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('Description', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    hintText: 'More details about this batch',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    alignLabelWithHint: true,
                  ),
                  style: GoogleFonts.poppins(),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Batch name is required')));
                  return;
                }
                setState(() {
                  _batches.add({
                    'id': '',
                    'name': name,
                    'description': descController.text.trim(),
                    'start_time': _timeOfDayToStr(startTime),
                    'end_time': _timeOfDayToStr(endTime),
                  });
                });
                Navigator.pop(ctx);
              },
              child: const Text('Create batch'),
            ),
          ],
        ),
      ),
    );
  }

  static const List<MapEntry<String, String>> _durationOptions = [
    MapEntry('1m', '1 Month (30 days)'),
    MapEntry('2m', '2 Months'),
    MapEntry('3m', '3 Months'),
    MapEntry('6m', '6 Months'),
    MapEntry('1yr', '1 Year'),
    MapEntry('one_time', 'One Time'),
  ];

  String _durationLabel(String? type) {
    if (type == null) return '';
    for (final e in _durationOptions) {
      if (e.key == type) return e.value;
    }
    return type;
  }

  void _showCreatePlanDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final priceController = TextEditingController(text: '1500');
    String durationType = '1m';
    int? registrationFee;
    bool waiveRegistrationFee = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isOneTime = durationType == 'one_time';
          return AlertDialog(
            title: Text('Create membership plan', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Plan name *', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    maxLength: 50,
                    decoration: InputDecoration(
                      hintText: 'e.g. Monthly Basic, Annual Premium',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    style: GoogleFonts.poppins(),
                  ),
                  const SizedBox(height: 16),
                  Text('Description', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descController,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: "Describe what's included in this plan",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    style: GoogleFonts.poppins(),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Text('Price (₹) *', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: priceController,
                    decoration: InputDecoration(
                      hintText: '₹ 1500',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    style: GoogleFonts.poppins(),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  Text('Duration *', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: durationType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    items: _durationOptions.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDialogState(() => durationType = v ?? '1m'),
                  ),
                  if (isOneTime) ...[
                    const SizedBox(height: 16),
                    Text('Initial registration fee (₹)', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'e.g. 1000 (added to every new member)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                      ),
                      style: GoogleFonts.poppins(),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        setDialogState(() => registrationFee = n);
                      },
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: Text('Waive registration fee', style: GoogleFonts.poppins(fontSize: 14)),
                      value: waiveRegistrationFee,
                      onChanged: (v) => setDialogState(() => waiveRegistrationFee = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan name is required')));
                    return;
                  }
                  final price = int.tryParse(priceController.text.trim());
                  if (price == null || price < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price')));
                    return;
                  }
                  setState(() {
                    _plans.add({
                      'id': '',
                      'name': name,
                      'description': descController.text.trim(),
                      'price': price,
                      'duration_type': durationType,
                      'is_active': true,
                      'registration_fee': isOneTime ? registrationFee : null,
                      'waive_registration_fee': isOneTime && waiveRegistrationFee,
                    });
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Create plan'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditPlanDialog(int index) {
    final p = _plans[index];
    final nameController = TextEditingController(text: p['name'] as String?);
    final descController = TextEditingController(text: p['description'] as String?);
    final priceController = TextEditingController(text: '${p['price'] ?? 0}');
    final regFeeController = TextEditingController(text: p['registration_fee'] != null ? '${p['registration_fee']}' : '');
    String durationType = p['duration_type'] as String? ?? '1m';
    bool waiveRegistrationFee = p['waive_registration_fee'] == true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isOneTime = durationType == 'one_time';
          return AlertDialog(
            title: Text('Edit membership plan', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Plan name *', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    maxLength: 50,
                    decoration: InputDecoration(
                      hintText: 'e.g. Monthly Basic',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    style: GoogleFonts.poppins(),
                  ),
                  const SizedBox(height: 16),
                  Text('Description', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descController,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: "What's included",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    style: GoogleFonts.poppins(),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Text('Price (₹) *', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: priceController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    style: GoogleFonts.poppins(),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  Text('Duration *', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: durationType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    items: _durationOptions.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDialogState(() => durationType = v ?? '1m'),
                  ),
                  if (isOneTime) ...[
                    const SizedBox(height: 16),
                    Text('Initial registration fee (₹)', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: regFeeController,
                      decoration: InputDecoration(
                        hintText: 'e.g. 1000',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                      ),
                      style: GoogleFonts.poppins(),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: Text('Waive registration fee', style: GoogleFonts.poppins(fontSize: 14)),
                      value: waiveRegistrationFee,
                      onChanged: (v) => setDialogState(() => waiveRegistrationFee = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan name is required')));
                    return;
                  }
                  final price = int.tryParse(priceController.text.trim());
                  if (price == null || price < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price')));
                    return;
                  }
                  final regFee = int.tryParse(regFeeController.text.trim());
                  setState(() {
                    _plans[index] = {
                      'id': p['id'],
                      'name': name,
                      'description': descController.text.trim(),
                      'price': price,
                      'duration_type': durationType,
                      'is_active': p['is_active'],
                      'registration_fee': isOneTime ? (regFee != null && regFee >= 0 ? regFee : null) : null,
                      'waive_registration_fee': isOneTime && waiveRegistrationFee,
                    };
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditBatchDialog(int index) {
    final b = _batches[index];
    final nameController = TextEditingController(text: b['name']);
    final descController = TextEditingController(text: b['description']);
    TimeOfDay _parseTime(String? s) {
      if (s == null || s.isEmpty) return const TimeOfDay(hour: 6, minute: 0);
      final parts = s.split(':');
      if (parts.isEmpty) return const TimeOfDay(hour: 6, minute: 0);
      final h = int.tryParse(parts[0]) ?? 6;
      final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    }
    TimeOfDay startTime = _parseTime(b['start_time']);
    TimeOfDay endTime = _parseTime(b['end_time']);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit batch', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Batch name', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Ladies/Morning, Gents/Evening',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                  ),
                  style: GoogleFonts.poppins(),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Text('Batch timings', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(_formatTimeDisplay(_timeOfDayToStr(startTime)), style: GoogleFonts.poppins()),
                        onPressed: () async {
                          final picked = await _showTimePickerAmPm(context, startTime);
                          if (picked != null) setDialogState(() => startTime = picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('to', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(_formatTimeDisplay(_timeOfDayToStr(endTime)), style: GoogleFonts.poppins()),
                        onPressed: () async {
                          final picked = await _showTimePickerAmPm(context, endTime);
                          if (picked != null) setDialogState(() => endTime = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Duration from start', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _batchDurationPresets.map((e) {
                    final end = _timeOfDayAddMinutes(startTime, e.value);
                    final selected = endTime.hour == end.hour && endTime.minute == end.minute;
                    return ChoiceChip(
                      label: Text(e.key, style: GoogleFonts.poppins(fontSize: 12)),
                      selected: selected,
                      onSelected: (_) => setDialogState(() => endTime = end),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('Description', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    hintText: 'More details about this batch',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    alignLabelWithHint: true,
                  ),
                  style: GoogleFonts.poppins(),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Batch name is required')));
                  return;
                }
                setState(() {
                  _batches[index] = {
                    'id': b['id'] ?? '',
                    'name': name,
                    'description': descController.text.trim(),
                    'start_time': _timeOfDayToStr(startTime),
                    'end_time': _timeOfDayToStr(endTime),
                  };
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.of(context).padding;
    if (_loading) {
      if (widget.embedded) {
        return const Center(child: CircularProgressIndicator());
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Gym settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final bodyContent = SingleChildScrollView(
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
          const SizedBox(height: 28),
          Text('Address Information', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          const SizedBox(height: 12),
          Text('Address Line 1', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
          const SizedBox(height: 6),
          TextField(
            controller: _addressLine1Controller,
            decoration: InputDecoration(
              hintText: 'Street address',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            ),
            style: GoogleFonts.poppins(),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          Text('Address Line 2', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
          const SizedBox(height: 6),
          TextField(
            controller: _addressLine2Controller,
            decoration: InputDecoration(
              hintText: 'Apartment, floor, etc.',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            ),
            style: GoogleFonts.poppins(),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          Text('City', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
          const SizedBox(height: 6),
          TextField(
            controller: _cityController,
            decoration: InputDecoration(
              hintText: 'e.g. Kolkata',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            ),
            style: GoogleFonts.poppins(),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          Text('State', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
          const SizedBox(height: 6),
          TextField(
            controller: _stateController,
            decoration: InputDecoration(
              hintText: 'Select state',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            ),
            style: GoogleFonts.poppins(),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          Text('PIN Code', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
          const SizedBox(height: 6),
          TextField(
            controller: _pinCodeController,
            decoration: InputDecoration(
              hintText: 'e.g. 400001',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              counterText: '',
            ),
            style: GoogleFonts.poppins(),
            keyboardType: TextInputType.number,
            maxLength: 10,
          ),
          const SizedBox(height: 14),
          Text('Phone number', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
          const SizedBox(height: 6),
          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              hintText: 'e.g. 9876543210',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              counterText: '',
            ),
            style: GoogleFonts.poppins(),
            keyboardType: TextInputType.phone,
            maxLength: 15,
          ),
          const SizedBox(height: 14),
          Text('Terms and conditions (for invoice PDF)', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
          const SizedBox(height: 6),
          TextField(
            controller: _termsController,
            decoration: InputDecoration(
              hintText: 'One line per point. e.g.\n1. Membership fees are non-refundable.\n2. This invoice is valid for the period mentioned.',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              alignLabelWithHint: true,
            ),
            style: GoogleFonts.poppins(),
            maxLines: 5,
            minLines: 3,
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Text('Batches', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _showCreateBatchDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create batch'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_batches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No batches yet. Add batches like Morning, Evening, Ladies, etc.',
                style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
              ),
            )
          else
            ..._batches.asMap().entries.map((e) {
              final i = e.key;
              final b = e.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Batch name', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _showEditBatchDialog(i),
                            tooltip: 'Edit batch',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () {
                              setState(() => _batches.removeAt(i));
                            },
                            tooltip: 'Remove batch',
                          ),
                        ],
                      ),
                      Text(b['name'] ?? '', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                      if ((b['start_time'] ?? '').isNotEmpty || (b['end_time'] ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${_formatTimeDisplay(b['start_time'])} – ${_formatTimeDisplay(b['end_time'])}',
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ),
                      if ((b['description'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Description', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 2),
                        Text(b['description'] ?? '', style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.onSurface)),
                      ],
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 28),
          Row(
            children: [
              Text('Membership Plans', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _showCreatePlanDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create plan'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_plans.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No membership plans yet. Create plans (e.g. Monthly Basic, Annual Premium, One Time) with price and duration.',
                style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
              ),
            )
          else
            ..._plans.asMap().entries.map((e) {
              final i = e.key;
              final p = e.value;
              final isActive = p['is_active'] != false;
              final durationLabel = _durationLabel(p['duration_type'] as String?);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(p['name'] as String? ?? '', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                                    if (!isActive) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(8)),
                                        child: Text('Deactivated', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white)),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('₹${p['price']}/$durationLabel', style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.primary)),
                                if ((p['description'] as String? ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(p['description'] as String, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _showEditPlanDialog(i),
                            tooltip: 'Edit plan',
                          ),
                          IconButton(
                            icon: Icon(isActive ? Icons.toggle_on : Icons.toggle_off, size: 36, color: isActive ? AppTheme.primary : Colors.grey),
                            onPressed: () {
                              setState(() => _plans[i] = Map<String, dynamic>.from(_plans[i])..['is_active'] = !isActive);
                            },
                            tooltip: isActive ? 'Deactivate plan' : 'Activate plan',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(_saving ? 'Saving...' : 'Save changes', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
    if (widget.embedded) {
      return bodyContent;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Gym settings', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => LoginScreen.logout(context),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
          ),
        ],
      ),
      body: bodyContent,
    );
  }
}
