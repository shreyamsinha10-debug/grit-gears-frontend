// ---------------------------------------------------------------------------
// Member detail – full profile, edit, payments, attendance, check-in/out.
// ---------------------------------------------------------------------------
// Opened from Members list when user taps a member. Shows [Member] info,
// payments list, attendance stats; [showMemberEditDialog] for edit; actions
// for check-in/out and mark payment paid. Uses [Member] from dashboard_screen.
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../core/image_compression.dart';
import '../theme/app_theme.dart';
import '../widgets/attendance_stats_card.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

/// Shows edit member dialog; returns updated [Member] on save, null on cancel.
Future<Member?> showMemberEditDialog(BuildContext context, Member m) async {
  // Fetch dynamic batches from gym settings
  List<String> batchNames = [];
  try {
    final r = await ApiClient.instance.get('/gym/profile', useCache: false);
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final batchList = data['batches'] as List<dynamic>? ?? [];
      batchNames = batchList
          .map((b) => ((b as Map<String, dynamic>)['name'] as String? ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  // Always include member's current batch so the dropdown has a valid value
  if (m.batch.isNotEmpty && !batchNames.contains(m.batch)) batchNames.insert(0, m.batch);
  if (batchNames.isEmpty) batchNames = ['Morning', 'Evening', 'Ladies'];

  // Training type: Regular or PT (derive from current membership_type for display)
  final isPT = m.membershipType.toLowerCase().contains('pt');
  String trainingType = isPT ? 'PT' : 'Regular';

  final nameController = TextEditingController(text: m.name);
  final phoneController = TextEditingController(text: m.phone);
  final emailController = TextEditingController(text: m.email);
  final addressController = TextEditingController(text: m.address ?? '');
  String batch = batchNames.contains(m.batch) ? m.batch : batchNames.first;
  String status = m.status;
  String? gender = m.gender;
  DateTime? dateOfBirth = m.dateOfBirth != null && m.dateOfBirth!.isNotEmpty ? DateTime.tryParse(m.dateOfBirth!) : null;
  final scheduleController = TextEditingController(text: m.workoutSchedule ?? '');
  final dietController = TextEditingController(text: m.dietChart ?? '');

  return showDialog<Member>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Edit member'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone, maxLength: 10, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
              const SizedBox(height: 12),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Address (optional)'), maxLines: 2),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: dateOfBirth ?? DateTime(2000),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => dateOfBirth = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: 'Date of birth (optional)'),
                  child: Text(dateOfBirth != null ? formatDisplayDate(dateOfBirth) : 'Select date of birth', style: TextStyle(color: dateOfBirth != null ? null : Colors.grey)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: gender,
                decoration: const InputDecoration(labelText: 'Gender (optional)'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Select gender')),
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                  DropdownMenuItem(value: 'Prefer not to say', child: Text('Prefer not to say')),
                ],
                onChanged: (v) => setDialogState(() => gender = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: trainingType,
                decoration: const InputDecoration(labelText: 'Training type'),
                items: const [
                  DropdownMenuItem(value: 'Regular', child: Text('Regular')),
                  DropdownMenuItem(value: 'PT', child: Text('PT (Personal Training)')),
                ],
                onChanged: (v) => setDialogState(() => trainingType = v ?? trainingType),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: batch,
                decoration: const InputDecoration(labelText: 'Batch'),
                items: batchNames
                    .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                    .toList(),
                onChanged: (v) => setDialogState(() => batch = v ?? batch),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                  DropdownMenuItem(value: 'Disabled', child: Text('Disabled')),
                ],
                onChanged: (v) => setDialogState(() => status = v ?? status),
              ),
              if (trainingType.toLowerCase() == 'pt') ...[
                const SizedBox(height: 12),
                TextField(controller: scheduleController, maxLines: 3, decoration: const InputDecoration(labelText: 'Workout schedule', alignLabelWithHint: true)),
                const SizedBox(height: 12),
                TextField(controller: dietController, maxLines: 3, decoration: const InputDecoration(labelText: 'Diet chart', alignLabelWithHint: true)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () async {
              final body = <String, dynamic>{
                'name': nameController.text.trim(),
                'phone': phoneController.text.trim(),
                'email': emailController.text.trim(),
                'batch': batch,
                'status': status,
                'membership_type': trainingType,
                'address': addressController.text.trim(),
                'date_of_birth': dateOfBirth != null ? formatApiDate(dateOfBirth!) : null,
                'gender': gender,
              };
              if (trainingType.toLowerCase() == 'pt') {
                body['workout_schedule'] = scheduleController.text;
                body['diet_chart'] = dietController.text;
              }
              try {
                final r = await ApiClient.instance.patch(
                  '/members/${m.id}',
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(body),
                );
                if (!ctx.mounted) return;
                if (r.statusCode >= 200 && r.statusCode < 300) {
                  final map = jsonDecode(r.body) as Map<String, dynamic>?;
                  if (map != null) Navigator.pop(ctx, Member.fromJson(map));
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: ${r.body}')));
                }
              } catch (e) {
                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Assign workout plan (plain text). Returns updated [Member] on save.
Future<Member?> showAssignWorkoutPlanDialog(BuildContext context, Member m) async {
  final controller = TextEditingController(text: m.workoutSchedule ?? '');
  return showDialog<Member>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Assign Workout Plan'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Enter workout plan in plain text...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            try {
              final r = await ApiClient.instance.patch(
                '/members/${m.id}',
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'workout_schedule': controller.text}),
              );
              if (!ctx.mounted) return;
              if (r.statusCode >= 200 && r.statusCode < 300) {
                final map = jsonDecode(r.body) as Map<String, dynamic>?;
                if (map != null) Navigator.pop(ctx, Member.fromJson(map));
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: ${r.body}')));
              }
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Assign diet plan (plain text). Returns updated [Member] on save.
Future<Member?> showAssignDietPlanDialog(BuildContext context, Member m) async {
  final controller = TextEditingController(text: m.dietChart ?? '');
  return showDialog<Member>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Assign Diet Plan'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Enter diet plan in plain text...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            try {
              final r = await ApiClient.instance.patch(
                '/members/${m.id}',
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'diet_chart': controller.text}),
              );
              if (!ctx.mounted) return;
              if (r.statusCode >= 200 && r.statusCode < 300) {
                final map = jsonDecode(r.body) as Map<String, dynamic>?;
                if (map != null) Navigator.pop(ctx, Member.fromJson(map));
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: ${r.body}')));
              }
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class MemberDetailScreen extends StatefulWidget {
  final Member member;

  const MemberDetailScreen({super.key, required this.member});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Member _member;
  Map<String, dynamic>? _attendanceStats;
  List<dynamic> _payments = [];
  List<dynamic> _attendanceList = [];
  bool _loadingPayments = true;
  bool _loadingAttendance = true;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _member = widget.member;
    _tabController = TabController(length: 4, vsync: this);
    _loadFullMember(); // Fetch full member (photo, id_document) in case list was brief
    _loadStats();
    _loadPayments();
    _loadAttendance();
  }

  /// Reload full member (including photo and ID document) from API.
  Future<void> _loadFullMember() async {
    try {
      final r = await ApiClient.instance.get('/members/${_member.id}', useCache: false);
      if (mounted && r.statusCode == 200) {
        final map = jsonDecode(r.body) as Map<String, dynamic>?;
        if (map != null) setState(() => _member = Member.fromJson(map));
      }
    } catch (_) {}
  }

  Future<String?> _pickImage() async {
    final XFile? file = await _imagePicker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (file == null) return null;
    Uint8List bytes = await file.readAsBytes();
    if (bytes.length > kMaxImageBytes) bytes = compressImageToMaxBytes(bytes);
    return base64Encode(bytes);
  }

  Future<(String, String)?> _pickIdDocument() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    List<int>? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      try { bytes = await File(file.path!).readAsBytes(); } catch (_) {}
    }
    if (bytes == null) return null;
    final bytesList = Uint8List.fromList(bytes);
    // Compress image ID documents (not PDF) to keep under 500 KB
    final toEncode = isCompressibleImage(bytesList) ? compressImageToMaxBytes(bytesList) : bytesList;
    const types = ['Aadhar', 'Driving Licence', 'Voter ID', 'Passport'];
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ID document type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: types.map((t) => ListTile(title: Text(t), onTap: () => Navigator.pop(ctx, t))).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
    if (type == null) return null;
    return (base64Encode(toEncode), type);
  }

  Future<void> _updateMemberPhoto(String? base64) async {
    try {
      final r = await ApiClient.instance.patch(
        '/members/${_member.id}/photo',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'photo_base64': base64}),
      );
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) await _loadFullMember();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().split('\n').first}')));
    }
  }

  Future<void> _updateMemberIdDocument(String? base64, String? type) async {
    try {
      final body = <String, dynamic>{'id_document_base64': base64};
      if (type != null) body['id_document_type'] = type;
      final r = await ApiClient.instance.patch(
        '/members/${_member.id}/id-document',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        await _loadFullMember();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(base64 != null ? 'ID document uploaded successfully' : 'ID document removed')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().split('\n').first}')));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final r = await ApiClient.instance.get('/members/${_member.id}/attendance-stats', useCache: false);
      if (mounted && r.statusCode == 200) {
        setState(() => _attendanceStats = jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _loadPayments() async {
    setState(() => _loadingPayments = true);
    try {
      final r = await ApiClient.instance.get('/payments', queryParameters: {'member_id': _member.id}, useCache: false);
      if (mounted && r.statusCode == 200) {
        setState(() {
          _payments = jsonDecode(r.body) as List<dynamic>;
          _loadingPayments = false;
        });
      } else if (mounted) setState(() => _loadingPayments = false);
    } catch (_) {
      if (mounted) setState(() => _loadingPayments = false);
    }
  }

  Future<void> _loadAttendance() async {
    setState(() => _loadingAttendance = true);
    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 90));
      final r = await ApiClient.instance.get('/attendance/by-date-range', queryParameters: {'date_from': formatApiDate(from), 'date_to': formatApiDate(now)}, useCache: false);
      if (mounted && r.statusCode == 200) {
        final all = jsonDecode(r.body) as List<dynamic>;
        setState(() {
          _attendanceList = all.where((e) => (e as Map<String, dynamic>)['member_id'] == _member.id).toList();
          _loadingAttendance = false;
        });
      } else if (mounted) setState(() => _loadingAttendance = false);
    } catch (_) {
      if (mounted) setState(() => _loadingAttendance = false);
    }
  }

  Future<void> _cancelMembership() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel membership?'),
        content: Text('Set ${_member.name} as Inactive? They will no longer be able to check in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, cancel')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final r = await ApiClient.instance.patch(
        '/members/${_member.id}',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': 'Inactive'}),
      );
      if (mounted) {
        if (r.statusCode >= 200 && r.statusCode < 300) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Membership cancelled')));
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${r.body}')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteMember() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          '${_member.name} will be set to Inactive and removed from the active list. You can re-activate later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _cancelMembership();
  }

  Future<void> _showEditDialog() async {
    final updated = await showMemberEditDialog(context, _member);
    if (updated != null && mounted) {
      setState(() => _member = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member updated')));
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final controller = TextEditingController();
    bool loading = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Reset Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Set a new password for ${_member.name}. They can use this to log in.',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (controller.text.length < 6) {
                        setDialogState(() => error = 'Password must be at least 6 characters');
                        return;
                      }
                      setDialogState(() { loading = true; error = null; });
                      try {
                        final r = await ApiClient.instance.patch(
                          '/members/${_member.id}/password',
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'new_password': controller.text}),
                        );
                        if (r.statusCode >= 200 && r.statusCode < 300) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset successfully')));
                        } else {
                          final msg = jsonDecode(r.body)['detail'] ?? 'Failed';
                          setDialogState(() { loading = false; error = msg.toString(); });
                        }
                      } catch (e) {
                        setDialogState(() { loading = false; error = 'Error: $e'; });
                      }
                    },
              child: loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _member;
    final padding = LayoutConstants.screenPadding(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Member Details', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          TextButton.icon(
            onPressed: m.status.toLowerCase() == 'active' ? _cancelMembership : null,
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: _showEditDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => LoginScreen.logout(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (v) {
              if (v == 'delete') _deleteMember();
              if (v == 'reset_password') _showResetPasswordDialog();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reset_password', child: Text('Reset / Assign Password')),
              const PopupMenuItem(value: 'delete', child: Text('Delete Member', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemberSummaryCard(member: m, padding: padding),
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Payments'),
              Tab(text: 'Attendance'),
              Tab(icon: Icon(Icons.list_alt, size: 20), text: 'Plans'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _OverviewTab(
                  member: m,
                  onUpdatePhoto: () async {
                    final b = await _pickImage();
                    if (b != null) await _updateMemberPhoto(b);
                  },
                  onRemovePhoto: () => _updateMemberPhoto(null),
                  onUpdateIdDocument: () async {
                    final pair = await _pickIdDocument();
                    if (pair != null) await _updateMemberIdDocument(pair.$1, pair.$2);
                  },
                  onRemoveIdDocument: () => _updateMemberIdDocument(null, null),
                ),
                _PaymentsTab(
                  payments: _payments,
                  loading: _loadingPayments,
                  onRefresh: _loadPayments,
                ),
                _AttendanceTab(
                  stats: _attendanceStats,
                  attendanceList: _attendanceList,
                  loading: _loadingAttendance,
                  lastVisit: m.lastAttendanceDate != null ? formatDisplayDate(m.lastAttendanceDate!) : '',
                  onRefresh: () async {
                    await _loadStats();
                    await _loadAttendance();
                  },
                ),
                _PlansTab(
                  member: m,
                  onMemberUpdated: (updated) {
                    if (mounted) setState(() => _member = updated);
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(padding, 12, padding, 12 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _showResetPasswordDialog,
                icon: const Icon(Icons.lock_reset, size: 20),
                label: const Text('Reset / Assign Password'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberSummaryCard extends StatelessWidget {
  final Member member;
  final double padding;

  const _MemberSummaryCard({required this.member, required this.padding});

  @override
  Widget build(BuildContext context) {
    final isActive = member.status.toLowerCase() == 'active';
    final memberSince = member.createdAt != null
        ? DateFormat('MMMM yyyy').format(member.createdAt!)
        : '—';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppTheme.primary.withOpacity(0.2),
            foregroundColor: AppTheme.primary,
            backgroundImage: member.photoBase64 != null
                ? MemoryImage(base64Decode(member.photoBase64!))
                : null,
            onBackgroundImageError: member.photoBase64 != null ? (_, __) {} : null,
            child: member.photoBase64 == null
                ? Text(
                    (member.name.isNotEmpty ? member.name[0] : '?').toUpperCase(),
                    style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.onSurface),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isActive ? AppTheme.success : Colors.grey).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    member.status,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: isActive ? AppTheme.success : Colors.grey.shade700),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Member since $memberSince',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Membership : ${member.membershipType}',
                  style: GoogleFonts.poppins(fontSize: 14, color: AppTheme.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final Member member;
  final Future<void> Function() onUpdatePhoto;
  final VoidCallback onRemovePhoto;
  final Future<void> Function() onUpdateIdDocument;
  final VoidCallback onRemoveIdDocument;

  const _OverviewTab({
    required this.member,
    required this.onUpdatePhoto,
    required this.onRemovePhoto,
    required this.onUpdateIdDocument,
    required this.onRemoveIdDocument,
  });

  @override
  Widget build(BuildContext context) {
    final padding = LayoutConstants.screenPadding(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile picture & ID document – upload, delete, re-upload
          Card(
            color: AppTheme.surfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.photo_camera_outlined, size: 20, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Profile & ID',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AppTheme.primary.withOpacity(0.2),
                        foregroundColor: AppTheme.primary,
                        backgroundImage: member.photoBase64 != null
                            ? MemoryImage(base64Decode(member.photoBase64!))
                            : null,
                        onBackgroundImageError: member.photoBase64 != null ? (_, __) {} : null,
                        child: member.photoBase64 == null
                            ? Text((member.name.isNotEmpty ? member.name[0] : '?').toUpperCase(), style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold))
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Profile picture', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonal(
                                  onPressed: () => onUpdatePhoto(),
                                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary.withOpacity(0.15), foregroundColor: AppTheme.primary),
                                  child: const Text('Change'),
                                ),
                                if (member.photoBase64 != null)
                                  OutlinedButton(
                                    onPressed: onRemovePhoto,
                                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error)),
                                    child: const Text('Remove'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (member.idDocumentBase64 != null)
                        GestureDetector(
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.all(16),
                              child: InteractiveViewer(
                                clipBehavior: Clip.none,
                                maxScale: 5.0,
                                child: Image.memory(
                                  base64Decode(member.idDocumentBase64!),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                              image: DecorationImage(
                                image: MemoryImage(base64Decode(member.idDocumentBase64!)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        )
                      else
                        Icon(Icons.badge_outlined, size: 24, color: AppTheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.idDocumentBase64 != null
                                  ? 'ID document: ${member.idDocumentType ?? 'Uploaded'}'
                                  : 'Identity document (Aadhar, Passport, etc.)',
                              style: GoogleFonts.poppins(fontSize: 14, color: AppTheme.onSurface),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonal(
                                  onPressed: () => onUpdateIdDocument(),
                                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary.withOpacity(0.15), foregroundColor: AppTheme.primary),
                                  child: Text(member.idDocumentBase64 != null ? 'Re-upload' : 'Upload'),
                                ),
                                if (member.idDocumentBase64 != null)
                                  OutlinedButton(
                                    onPressed: onRemoveIdDocument,
                                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error)),
                                    child: const Text('Remove'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: AppTheme.surfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 20, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Contact Information',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _contactRow(Icons.email_outlined, 'Email', member.email),
                  _contactRow(Icons.phone_android_outlined, 'Phone', member.phone),
                  _contactRow(Icons.location_on_outlined, 'Address', member.address ?? '—'),
                  _contactRow(Icons.person_outline, 'Gender', member.gender ?? '—'),
                  _contactRow(Icons.cake_outlined, 'Date of Birth', member.dateOfBirth != null && member.dateOfBirth!.isNotEmpty ? (formatDisplayDate(parseApiDate(member.dateOfBirth)) ?? member.dateOfBirth!) : '—'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.poppins(fontSize: 14, color: AppTheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  final List<dynamic> payments;
  final bool loading;
  final VoidCallback onRefresh;

  const _PaymentsTab({
    required this.payments,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    final padding = LayoutConstants.screenPadding(context);
    if (payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Payment history — period and date received', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            const SizedBox(height: 8),
            Text('No payments yet', style: GoogleFonts.poppins(color: Colors.grey)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        ApiClient.instance.invalidateCache();
        onRefresh();
      },
      child: ListView(
        padding: EdgeInsets.all(padding),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Payment history — period and date received',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
            ),
          ),
          ...payments.map<Widget>((e) {
            final p = e as Map<String, dynamic>;
            final paidAt = p['paid_at'];
            final paidDateStr = paidAt != null ? formatDisplayDate(parseApiDateTime(paidAt.toString())) : null;
            final isPaid = p['status'] == 'Paid';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${p['fee_type']} • ${p['period'] ?? 'Registration'}', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('₹${p['amount']}', style: GoogleFonts.poppins(color: AppTheme.primary)),
                    if (isPaid && paidDateStr != null)
                      Text('Paid on $paidDateStr', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AttendanceTab extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final List<dynamic> attendanceList;
  final bool loading;
  final String lastVisit;
  final Future<void> Function() onRefresh;

  const _AttendanceTab({
    required this.stats,
    required this.attendanceList,
    required this.loading,
    required this.lastVisit,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    final padding = LayoutConstants.screenPadding(context);
    return RefreshIndicator(
      onRefresh: () async {
        ApiClient.instance.invalidateCache();
        await onRefresh();
      },
      child: ListView(
        padding: EdgeInsets.all(padding),
        children: [
          AttendanceStatsWidget(
            totalVisits: stats?['total_visits'] ?? 0,
            visitsThisMonth: stats?['visits_this_month'] ?? 0,
            avgDurationMinutes: stats?['avg_duration_minutes'],
            lastVisit: lastVisit,
          ),
          const SizedBox(height: 20),
          Text(
            'Recent attendance',
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
          ),
          const SizedBox(height: 12),
          if (attendanceList.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(child: Text('No attendance records', style: GoogleFonts.poppins(color: Colors.grey))),
            )
          else
            ...attendanceList.map<Widget>((e) {
              final a = e as Map<String, dynamic>;
              final checkInDt = parseApiDateTime(a['check_in_at']?.toString());
              final checkOutDt = parseApiDateTime(a['check_out_at']?.toString());
              final inStr = formatDisplayTime(checkInDt);
              final outStr = checkOutDt != null ? formatDisplayTime(checkOutDt) : '—';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(a['date_ist'] ?? '', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  subtitle: Text('${a['batch']} • In: $inStr • Out: $outStr'),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PlansTab extends StatelessWidget {
  final Member member;
  final void Function(Member updated) onMemberUpdated;

  const _PlansTab({required this.member, required this.onMemberUpdated});

  @override
  Widget build(BuildContext context) {
    final isPT = member.membershipType.toLowerCase() == 'pt';
    final padding = LayoutConstants.screenPadding(context);

    if (!isPT) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Text(
            'Plans are only available for Personal Training (PT) members. Change membership type to PT in Edit to assign workout and diet plans.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 14),
          ),
        ),
      );
    }

    final hasWorkout = (member.workoutSchedule ?? '').trim().isNotEmpty;
    final hasDiet = (member.dietChart ?? '').trim().isNotEmpty;
    final hasAnyPlan = hasWorkout || hasDiet;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasAnyPlan) ...[
            const SizedBox(height: 24),
            Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange.shade700),
            const SizedBox(height: 16),
            Text(
              'No Plans Assigned',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'No workout or diet plans assigned to this member yet. Assign plans to help them achieve their fitness goals.',
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                final updated = await showAssignWorkoutPlanDialog(context, member);
                if (updated != null) onMemberUpdated(updated);
              },
              icon: const Icon(FontAwesomeIcons.dumbbell, size: 20),
              label: const Text('Assign Workout Plan'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final updated = await showAssignDietPlanDialog(context, member);
                if (updated != null) onMemberUpdated(updated);
              },
              icon: const Icon(FontAwesomeIcons.utensils, size: 20),
              label: const Text('Assign Diet Plan'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ] else ...[
            if (hasWorkout) ...[
              Card(
                color: AppTheme.surfaceVariant,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(FontAwesomeIcons.dumbbell, size: 20, color: AppTheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Workout Plan',
                                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final updated = await showAssignWorkoutPlanDialog(context, member);
                              if (updated != null) onMemberUpdated(updated);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        member.workoutSchedule!,
                        style: GoogleFonts.poppins(fontSize: 14, color: AppTheme.onSurface, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (hasDiet) ...[
              Card(
                color: AppTheme.surfaceVariant,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(FontAwesomeIcons.utensils, size: 20, color: AppTheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Diet Plan',
                                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final updated = await showAssignDietPlanDialog(context, member);
                              if (updated != null) onMemberUpdated(updated);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        member.dietChart!,
                        style: GoogleFonts.poppins(fontSize: 14, color: AppTheme.onSurface, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (!hasWorkout)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final updated = await showAssignWorkoutPlanDialog(context, member);
                        if (updated != null) onMemberUpdated(updated);
                      },
                      icon: const Icon(FontAwesomeIcons.dumbbell, size: 18),
                      label: const Text('Assign Workout Plan'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                if (!hasWorkout && !hasDiet) const SizedBox(width: 12),
                if (!hasDiet)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final updated = await showAssignDietPlanDialog(context, member);
                        if (updated != null) onMemberUpdated(updated);
                      },
                      icon: const Icon(FontAwesomeIcons.utensils, size: 18),
                      label: const Text('Assign Diet Plan'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
