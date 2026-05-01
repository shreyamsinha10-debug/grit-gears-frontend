// ---------------------------------------------------------------------------
// Member home – post-login screen for a member: check-in/out, payments, profile.
// ---------------------------------------------------------------------------
// Receives [member] map from login. Shows today's check-in/out buttons,
// payment dues list, and profile/attendance summary. All API calls use
// member id from [widget.member].
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../core/image_compression.dart';
import '../core/pdf_invoice_helper.dart';
import '../core/push_notifications.dart';
import '../core/secure_storage.dart';
import '../models/models.dart';
import '../widgets/skeleton_loading.dart';
import '../widgets/attendance_stats_card.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'member_inbox_screen.dart';

class MemberHomeScreen extends StatefulWidget {
  final Member member;

  const MemberHomeScreen({super.key, required this.member});

  @override
  State<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends State<MemberHomeScreen> with SingleTickerProviderStateMixin {
  List<dynamic> _payments = [];
  List<Invoice> _paymentHistory = [];
  bool _loadingPayments = false;
  bool _loadingPaymentHistory = false;
  bool _checkingIn = false;
  bool _checkingOut = false;
  bool _checkedInToday = false;
  bool _checkedOutToday = false;
  final GlobalKey _inboxKey = GlobalKey();
  /// Full member (photo, id_document) from GET /members/{id}; null until loaded.
  Member? _fullMember;
  final ImagePicker _imagePicker = ImagePicker();
  Map<String, dynamic>? _attendanceStats;
  bool _loadingStats = true;
  int _inboxCount = 0;
  AnimationController? _ambientController;
  final GlobalKey _profileIdCardKey = GlobalKey();
  String? _activeWorkoutPreset = 'Chest Day';

  void _ensureAmbientController() {
    _ambientController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat(reverse: true);
  }

  @override
  void initState() {
    super.initState();
    _activeWorkoutPreset ??= 'Chest Day';
    _ensureAmbientController();
    _checkedInToday = widget.member.isCheckedInToday ?? false;
    _checkedOutToday = widget.member.isCheckedOutToday ?? false;
    PushNotifications.initForMember(widget.member.id);
    _loadPayments();
    _loadPaymentHistory();
    _loadFullMember();
    _loadStats();
    _loadInboxCount();
  }

  @override
  void dispose() {
    _ambientController?.dispose();
    super.dispose();
  }

  Future<void> _loadInboxCount() async {
    try {
      final r = await ApiClient.instance.get('/messages/inbox', useCache: false);
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        final list = jsonDecode(r.body) as List<dynamic>? ?? [];
        setState(() => _inboxCount = list.length);
      }
    } catch (_) {}
  }

  Future<void> _loadStats() async {
    final mid = widget.member.id;
    if (mid.isEmpty) return;
    setState(() => _loadingStats = true);
    try {
      final r = await ApiClient.instance.get('/members/$mid/attendance-stats', useCache: false);
      if (mounted && r.statusCode == 200) {
        setState(() {
          _attendanceStats = jsonDecode(r.body) as Map<String, dynamic>;
          _loadingStats = false;
        });
      } else if (mounted && r.statusCode == 403) {
        final body = jsonDecode(r.body) as Map<String, dynamic>?;
        final detail = body?['detail']?.toString() ?? '';
        if (detail.toLowerCase().contains('portal') || detail.toLowerCase().contains('not active') || detail.toLowerCase().contains('blocked')) {
          await SecureStorage.setAuthToken(null);
          await SecureStorage.setAuthRole(null);
          ApiClient.setAuthToken(null);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => LoginScreen(initialMessage: detail.isNotEmpty ? detail : 'Portal access is blocked. Your membership is not active.')),
            );
          }
        }
        setState(() => _loadingStats = false);
      } else if (mounted) setState(() => _loadingStats = false);
    } catch (_) {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _loadFullMember() async {
    final mid = widget.member.id;
    if (mid.isEmpty) return;
    try {
      final r = await ApiClient.instance.get('/members/$mid', useCache: false);
      if (mounted && r.statusCode == 200) {
        setState(() {
          _fullMember = ApiClient.parseMember(r.body);
          _checkedInToday = _fullMember?.isCheckedInToday ?? false;
          _checkedOutToday = _fullMember?.isCheckedOutToday ?? false;
        });
      } else if (mounted && r.statusCode == 403) {
        final body = jsonDecode(r.body) as Map<String, dynamic>?;
        final detail = body?['detail']?.toString() ?? '';
        if (detail.toLowerCase().contains('portal') || detail.toLowerCase().contains('not active') || detail.toLowerCase().contains('blocked')) {
          await SecureStorage.setAuthToken(null);
          await SecureStorage.setAuthRole(null);
          ApiClient.setAuthToken(null);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => LoginScreen(initialMessage: detail.isNotEmpty ? detail : 'Portal access is blocked. Your membership is not active.')),
            );
          }
        }
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
    if (bytes == null) return null;
    final bytesList = Uint8List.fromList(bytes);
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

  Future<void> _updatePhoto(String? base64) async {
    final mid = widget.member.id;
    if (mid.isEmpty) return;
    try {
      final r = await ApiClient.instance.patch(
        '/members/$mid/photo',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'photo_base64': base64}),
      );
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) await _loadFullMember();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().split('\n').first}')));
    }
  }

  Future<void> _updateIdDocument(String? base64, String? type) async {
    final mid = widget.member.id;
    if (mid.isEmpty) return;
    try {
      final body = <String, dynamic>{'id_document_base64': base64};
      if (type != null) body['id_document_type'] = type;
      final r = await ApiClient.instance.patch(
        '/members/$mid/id-document',
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

  Future<void> _checkInSelf() async {
    final mid = widget.member.id;
    if (mid.isEmpty || _checkingIn) return;
    setState(() => _checkingIn = true);
    try {
      final r = await ApiClient.instance.post('/attendance/check-in/$mid');
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        hapticSuccess();
        setState(() { _checkedInToday = true; _checkingIn = false; });
        _loadStats();
        _loadFullMember();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checked in successfully!')),
        );
      } else {
        final body = jsonDecode(r.body) as Map<String, dynamic>?;
        final detail = body?['detail']?.toString() ?? 'Check-in failed';
        setState(() => _checkingIn = false);
        if (detail.toLowerCase().contains('already') || detail.toLowerCase().contains('today')) {
          setState(() => _checkedInToday = true);
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingIn = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().split('\n').first}')));
      }
    }
  }

  Future<void> _checkOutSelf() async {
    final mid = widget.member.id;
    if (mid.isEmpty || _checkingOut) return;
    setState(() => _checkingOut = true);
    try {
      final r = await ApiClient.instance.post('/attendance/check-out/$mid');
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        hapticSuccess();
        setState(() { _checkedOutToday = true; _checkingOut = false; });
        _loadStats();
        _loadFullMember();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checked out successfully!')));
      } else {
        final body = jsonDecode(r.body) as Map<String, dynamic>?;
        final detail = body?['detail']?.toString() ?? 'Check-out failed';
        setState(() => _checkingOut = false);
        if (detail.toLowerCase().contains('already')) setState(() => _checkedOutToday = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().split('\n').first}')));
      }
    }
  }

  Future<void> _loadPayments() async {
    final mid = widget.member.id;
    if (mid.isEmpty) return;
    setState(() => _loadingPayments = true);
    try {
      final r = await ApiClient.instance.get('/payments', queryParameters: {'member_id': mid}, useCache: false);
      if (mounted && r.statusCode >= 200 && r.statusCode < 300)
        setState(() { _payments = jsonDecode(r.body) as List<dynamic>; _loadingPayments = false; });
      else if (mounted) setState(() => _loadingPayments = false);
    } catch (_) {
      if (mounted) setState(() => _loadingPayments = false);
    }
  }

  Future<void> _loadPaymentHistory() async {
    final mid = widget.member.id;
    if (mid.isEmpty) return;
    setState(() => _loadingPaymentHistory = true);
    try {
      final r = await ApiClient.instance.get('/billing/history', queryParameters: {'member_id': mid}, useCache: false);
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        final list = ApiClient.parseInvoices(r.body);
        final paidOnly = list.where((e) {
          final s = e.status.trim().toLowerCase();
          // Keep behavior aligned with admin payment history intent:
          // show invoices that are explicitly paid, or have a paid timestamp.
          return s == 'paid' || e.paidAt != null;
        }).toList();
        setState(() {
          _paymentHistory = paidOnly;
          _loadingPaymentHistory = false;
        });
      } else if (mounted) {
        setState(() => _loadingPaymentHistory = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPaymentHistory = false);
    }
  }

  bool get _isPT => widget.member.membershipType.toLowerCase() == 'pt';

  List<Map<String, dynamic>> get _paidPayments {
    return _payments
        .where((p) => (p['status']?.toString().toLowerCase() ?? '') == 'paid')
        .map((p) => p as Map<String, dynamic>)
        .toList();
  }

  List<Map<String, dynamic>> get _duePayments {
    // UI-only hide as requested. Backend due rows remain unchanged.
    return const <Map<String, dynamic>>[];
  }

  bool get _hasOverdue => _duePayments.any((p) => p['status'] == 'Overdue');

  Widget _animatedReveal({
    required Widget child,
    int order = 0,
  }) {
    final start = (order * 0.12).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 860 + (order * 70)),
      curve: Curves.easeOutBack,
      builder: (context, value, w) {
        final t = ((value - start) / (1 - start)).clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 26),
            child: w,
          ),
        );
      },
      child: child,
    );
  }

  Widget _breathingHighlight({required Widget child}) {
    return child;
  }

  Widget _ambientFloat({required Widget child, required int order}) {
    return child;
  }

  Widget _buildRestructuredScreen({
    required BuildContext context,
    required Member m,
    required String name,
    required String batch,
    required String status,
    required String lastAttendance,
    required String workoutSchedule,
    required String dietChart,
    required double padding,
    required double radius,
    required bool isActive,
  }) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        appBar: AppBar(
          title: Row(
            children: [
              Image.asset(
                defaultLogoAsset,
                height: 36,
                width: 36,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.fitness_center, color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(defaultGymName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFFFFFFF),
          foregroundColor: AppTheme.onSurface,
          actions: [
            IconButton(
              icon: _inboxCount > 0
                  ? Badge(
                      label: Text('$_inboxCount', style: const TextStyle(fontSize: 10)),
                      child: const Icon(Icons.inbox_rounded),
                    )
                  : const Icon(Icons.inbox_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberInboxScreen())).then((_) => _loadInboxCount()),
              tooltip: 'Inbox',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: () => LoginScreen.logout(context),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFFFFF), Color(0xFFFAF7EF), Color(0xFFF8F8F8)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width < 420 ? 10 : padding,
                vertical: MediaQuery.of(context).size.width < 420 ? 12 : padding,
              ),
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 980;
                    final gap = wide ? 24.0 : 16.0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 2, child: _buildProfileCard(name, batch, status, lastAttendance, isActive, padding, radius)),
                              SizedBox(width: gap),
                              Expanded(child: _buildMessagesCard(padding, radius)),
                            ],
                          )
                        else ...[
                          _buildProfileCard(name, batch, status, lastAttendance, isActive, padding, radius),
                          SizedBox(height: gap),
                          _buildMessagesCard(padding, radius),
                        ],
                        SizedBox(height: gap),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildProfileIdCard(name, padding, radius)),
                              SizedBox(width: gap),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildPaymentHistorySection(context, padding, radius),
                                    SizedBox(height: gap),
                                    _buildInboxSection(context, padding, radius, _inboxKey),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _buildProfileIdCard(name, padding, radius),
                          SizedBox(height: gap),
                          _buildPaymentHistorySection(context, padding, radius),
                          SizedBox(height: gap),
                          _buildInboxSection(context, padding, radius, _inboxKey),
                        ],
                        SizedBox(height: gap),
                        _buildAttendanceSection(lastAttendance, isActive, padding, radius),
                        SizedBox(height: gap),
                        _buildWorkoutSection(workoutSchedule, dietChart, padding, radius),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(String name, String batch, String status, String lastAttendance, bool isActive, double padding, double radius) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final ultraNarrow = constraints.maxWidth < 280;
        final avatarSize = compact ? 54.0 : 72.0;
        return _LuxuryCard(
          padding: EdgeInsets.all(compact ? 12 : padding),
          borderRadius: BorderRadius.circular(radius),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ultraNarrow)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: avatarSize,
                            height: avatarSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                              gradient: LinearGradient(colors: [const Color(0xFFD4AF37).withOpacity(0.24), const Color(0xFFF5E6A3).withOpacity(0.14)]),
                            ),
                            child: Center(
                              child: Text(
                                (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF9A7410)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurface),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _chip('Batch: $batch', const Color(0xFFD4AF37).withOpacity(0.14), const Color(0xFF9A7410)),
                              _chip('Status: $status', isActive ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12), isActive ? Colors.green.shade700 : Colors.orange.shade700),
                            ],
                          ),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: avatarSize,
                            height: avatarSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                              gradient: LinearGradient(colors: [const Color(0xFFD4AF37).withOpacity(0.24), const Color(0xFFF5E6A3).withOpacity(0.14)]),
                            ),
                            child: Center(
                              child: Text(
                                (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                                style: GoogleFonts.poppins(fontSize: compact ? 20 : 26, fontWeight: FontWeight.w700, color: const Color(0xFF9A7410)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.onSurface),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _chip('Batch: $batch', const Color(0xFFD4AF37).withOpacity(0.14), const Color(0xFF9A7410)),
                                    _chip('Status: $status', isActive ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12), isActive ? Colors.green.shade700 : Colors.orange.shade700),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text('Last check-in: ${lastAttendance.isEmpty ? '—' : lastAttendance}', style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          if (_profileIdCardKey.currentContext != null) {
                            Scrollable.ensureVisible(_profileIdCardKey.currentContext!, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
                          }
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Profile'),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                        gradient: LinearGradient(colors: [const Color(0xFFD4AF37).withOpacity(0.24), const Color(0xFFF5E6A3).withOpacity(0.14)]),
                      ),
                      child: Center(
                        child: Text(
                          (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                          style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: const Color(0xFF9A7410)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chip('Batch: $batch', const Color(0xFFD4AF37).withOpacity(0.14), const Color(0xFF9A7410)),
                              _chip('Status: $status', isActive ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12), isActive ? Colors.green.shade700 : Colors.orange.shade700),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Last check-in: ${lastAttendance.isEmpty ? '—' : lastAttendance}', style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () {
                        if (_profileIdCardKey.currentContext != null) {
                          Scrollable.ensureVisible(_profileIdCardKey.currentContext!, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
                        }
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit Profile'),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildMessagesCard(double padding, double radius) {
    return _LuxuryCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberInboxScreen())).then((_) => _loadInboxCount()),
      padding: EdgeInsets.all(padding),
      borderRadius: BorderRadius.circular(radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(Icons.mail_outline_rounded, color: AppTheme.primary), const SizedBox(width: 8), Text('Messages', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600))]),
          const SizedBox(height: 14),
          Text('$_inboxCount', style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
          const SizedBox(height: 4),
          Text(_inboxCount == 0 ? 'No unread messages' : 'Unread updates from your gym', style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildProfileIdCard(String name, double padding, double radius) {
    final hasPhoto = _fullMember?.photoBase64 != null && _fullMember!.photoBase64!.isNotEmpty;
    final hasId = _fullMember?.idDocumentBase64 != null && _fullMember!.idDocumentBase64!.isNotEmpty;
    return Container(
      key: _profileIdCardKey,
      child: _LuxuryCard(
        padding: EdgeInsets.all(padding),
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile & ID', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            _UploadPreviewTile(
              title: 'Profile Photo Upload',
              preview: hasPhoto ? Image.memory(base64Decode(_fullMember!.photoBase64!), fit: BoxFit.cover) : Center(child: Text((name.isNotEmpty ? name[0] : '?').toUpperCase(), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700))),
              onChange: () async {
                final b = await _pickImage();
                if (b != null) await _updatePhoto(b);
              },
              onRemove: hasPhoto ? () => _updatePhoto(null) : null,
            ),
            const SizedBox(height: 12),
            _UploadPreviewTile(
              title: 'ID Upload',
              preview: hasId ? Image.memory(base64Decode(_fullMember!.idDocumentBase64!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.badge_outlined, size: 34)) : const Icon(Icons.badge_outlined, size: 34),
              onChange: () async {
                final pair = await _pickIdDocument();
                if (pair != null) await _updateIdDocument(pair.$1, pair.$2);
              },
              onRemove: hasId ? () => _updateIdDocument(null, null) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummaryCard(double padding, double radius) {
    final paidInvoiceDate = _paymentHistory
        .where((e) => e.paidAt != null)
        .map((e) => e.paidAt!)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    final paidPaymentDate = _paidPayments
        .map((p) => DateTime.tryParse((p['paid_at'] ?? '').toString()))
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    final paidDate = switch ((paidInvoiceDate, paidPaymentDate)) {
      (null, null) => null,
      (DateTime a?, null) => a,
      (null, DateTime b?) => b,
      (DateTime a?, DateTime b?) => b.isAfter(a) ? b : a,
    };

    // Summary uses raw payment rows so it still works even if due UI is hidden.
    final dueRows = _payments.where((p) {
      final status = (p['status'] ?? '').toString().trim().toLowerCase();
      return status == 'due' || status == 'overdue';
    }).cast<Map<String, dynamic>>().toList();

    final dueAmount = dueRows.fold<num>(0, (sum, p) => sum + ((p['amount'] as num?) ?? 0));
    final dueDates = dueRows
        .map((p) => DateTime.tryParse((p['due_date'] ?? '').toString()))
        .whereType<DateTime>()
        .toList()
      ..sort();
    final nextDue = dueDates.isNotEmpty ? formatDisplayDate(dueDates.first) : '—';
    return _LuxuryCard(
      padding: EdgeInsets.all(padding),
      borderRadius: BorderRadius.circular(radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Summary', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          _statLine('Last payment', paidDate != null ? formatDisplayDate(paidDate) : '—', highlight: false),
          const SizedBox(height: 10),
          _statLine('Due amount', '₹$dueAmount', highlight: true),
          const SizedBox(height: 10),
          _statLine('Next due date', nextDue, highlight: false),
        ],
      ),
    );
  }

  Widget _buildAttendanceSection(String lastAttendance, bool isActive, double padding, double radius) {
    final total = (_attendanceStats?['total_visits'] ?? 0).toString();
    final month = (_attendanceStats?['visits_this_month'] ?? 0).toString();
    final avg = (_attendanceStats?['avg_duration_minutes'] ?? 0).toString();
    final last = lastAttendance.isEmpty ? '—' : lastAttendance;
    return _LuxuryCard(
      padding: EdgeInsets.all(padding),
      borderRadius: BorderRadius.circular(radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attendance Stats', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AttendanceStatTile(icon: Icons.fitness_center_outlined, label: 'Total Visits', value: total),
              _AttendanceStatTile(icon: Icons.calendar_month_outlined, label: 'This Month', value: month),
              _AttendanceStatTile(icon: Icons.timelapse_outlined, label: 'Avg Time', value: '$avg min'),
              _AttendanceStatTile(icon: Icons.history_toggle_off, label: 'Last Visit', value: last),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_checkedInToday || _checkingIn || !isActive) ? null : _checkInSelf,
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(_checkedInToday ? 'Checked in' : 'Check In'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_checkedOutToday || _checkingOut || !_checkedInToday || !isActive) ? null : _checkOutSelf,
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text(_checkedOutToday ? 'Checked out' : 'Check Out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutSection(String workoutSchedule, String dietChart, double padding, double radius) {
    final presets = const ['Chest Day', 'Leg Day', 'Back Day', 'Shoulder Day', 'Arm Day', 'Full Body'];
    final selectedPreset = _activeWorkoutPreset ?? 'Chest Day';
    return _LuxuryCard(
      padding: EdgeInsets.all(padding),
      borderRadius: BorderRadius.circular(radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Workout Plan', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (_isPT) ...[
            if (workoutSchedule.isNotEmpty) SelectableText(workoutSchedule, style: GoogleFonts.poppins(color: AppTheme.onSurface)),
            if (dietChart.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(dietChart, style: GoogleFonts.poppins(color: AppTheme.onSurfaceVariant)),
            ],
            if (workoutSchedule.isEmpty && dietChart.isEmpty) Text('No schedule or diet assigned yet.', style: GoogleFonts.poppins(color: Colors.grey)),
          ] else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: presets.whereType<String>().map((preset) {
                final active = selectedPreset == preset;
                return ChoiceChip(
                  label: Text(preset),
                  selected: active,
                  onSelected: (_) => setState(() => _activeWorkoutPreset = preset),
                  showCheckmark: false,
                  labelStyle: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: active ? const Color(0xFF6F5200) : AppTheme.onSurface,
                  ),
                  selectedColor: const Color(0xFFD4AF37).withOpacity(0.24),
                  backgroundColor: Colors.white.withOpacity(0.84),
                  side: BorderSide(color: active ? const Color(0xFFD4AF37) : const Color(0xFFE6D9AE)),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: GoogleFonts.poppins(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _statLine(String label, String value, {required bool highlight}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.onSurfaceVariant)),
        Text(
          value,
          style: GoogleFonts.poppins(fontSize: highlight ? 24 : 15, fontWeight: FontWeight.w700, color: highlight ? const Color(0xFFB68A10) : AppTheme.onSurface),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureAmbientController();
    final m = _fullMember ?? widget.member;
    final name = m.name;
    final batch = m.batch;
    final status = m.status;
    final lastAttendance = m.lastAttendanceDate != null ? formatDisplayDate(m.lastAttendanceDate) : '';
    final workoutSchedule = m.workoutSchedule ?? '';
    final dietChart = m.dietChart ?? '';
    final padding = LayoutConstants.screenPadding(context);
    final radius = LayoutConstants.cardRadius(context);
    final isActive = (status.toLowerCase() == 'active');

    final useStructuredLayout = DateTime.now().millisecondsSinceEpoch >= 0;
    if (useStructuredLayout) {
      return _buildRestructuredScreen(
        context: context,
        m: m,
        name: name,
        batch: batch,
        status: status,
        lastAttendance: lastAttendance,
        workoutSchedule: workoutSchedule,
        dietChart: dietChart,
        padding: padding,
        radius: radius,
        isActive: isActive,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        // From member home, hardware back should close the app instead of navigating back to login.
        SystemNavigator.pop();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              defaultLogoAsset,
              height: 36,
              width: 36,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.fitness_center, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(defaultGymName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: AppTheme.onSurface,
        actions: [
          IconButton(
            icon: _inboxCount > 0
                ? Badge(
                    label: Text('$_inboxCount', style: const TextStyle(fontSize: 10)),
                    child: const Icon(Icons.inbox_rounded),
                  )
                : const Icon(Icons.inbox_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberInboxScreen())).then((_) => _loadInboxCount()),
            tooltip: 'Inbox',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => LoginScreen.logout(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFFFFF), Color(0xFFFAF7EF), Color(0xFFF8F8F8)],
                ),
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFD4AF37).withOpacity(0.20),
                      const Color(0xFFD4AF37).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -50,
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFF5E6A3).withOpacity(0.25),
                      const Color(0xFFF5E6A3).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(padding),
            child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ambientFloat(
                order: 0,
                child: _animatedReveal(
                order: 0,
                child: _LuxuryCard(
                padding: EdgeInsets.all(padding),
                borderRadius: BorderRadius.circular(radius + 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Member Profile',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF9A7410),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFD4AF37).withOpacity(0.34),
                                const Color(0xFFF5E6A3).withOpacity(0.18),
                              ],
                            ),
                            border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.45)),
                          ),
                          child: Center(
                            child: Text(
                              (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFB68A10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(name, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.onSurface)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37).withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('Batch: $batch', style: GoogleFonts.poppins(color: const Color(0xFF9A7410), fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.green.withOpacity(0.10) : Colors.orange.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('Status: $status', style: GoogleFonts.poppins(color: isActive ? Colors.green.shade700 : Colors.orange.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    if (lastAttendance.isNotEmpty) Text('Last check-in: $lastAttendance', style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              ),
              ),
              ),
              const SizedBox(height: 16),
              _ambientFloat(
                order: 1,
                child: _animatedReveal(
                order: 1,
                child: _LuxuryCard(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberInboxScreen())).then((_) => _loadInboxCount()),
                padding: EdgeInsets.all(padding),
                borderRadius: BorderRadius.circular(radius + 2),
                child: Row(
                  children: [
                    Icon(Icons.inbox_rounded, size: 28, color: AppTheme.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Messages', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                          Text(
                            _inboxCount == 0 ? 'No new messages' : '$_inboxCount message${_inboxCount == 1 ? '' : 's'} from gym',
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    if (_inboxCount > 0) Icon(Icons.chevron_right, color: AppTheme.primary),
                  ],
                ),
              ),
              ),
              ),
              const SizedBox(height: 16),
              // Profile picture & ID document – upload, delete, re-upload (member can update own)
              _ambientFloat(
                order: 2,
                child: _LuxuryCard(
                padding: EdgeInsets.all(padding),
                borderRadius: BorderRadius.circular(radius),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.photo_camera_outlined, size: 20, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Text('Profile & ID', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: AppTheme.primary.withOpacity(0.2),
                            foregroundColor: AppTheme.primary,
                            backgroundImage: _fullMember?.photoBase64 != null && _fullMember!.photoBase64!.isNotEmpty
                                ? MemoryImage(base64Decode(_fullMember!.photoBase64!))
                                : null,
                            onBackgroundImageError: _fullMember?.photoBase64 != null && _fullMember!.photoBase64!.isNotEmpty ? (_, __) {} : null,
                            child: _fullMember?.photoBase64 == null || _fullMember!.photoBase64!.isEmpty
                                ? Text((name.isNotEmpty ? name[0] : '?').toUpperCase(), style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold))
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
                                      onPressed: () async {
                                        final b = await _pickImage();
                                        if (b != null) await _updatePhoto(b);
                                      },
                                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary.withOpacity(0.15), foregroundColor: AppTheme.primary),
                                      child: const Text('Change'),
                                    ),
                                    if (_fullMember?.photoBase64 != null && _fullMember!.photoBase64!.isNotEmpty)
                                      OutlinedButton(
                                        onPressed: () => _updatePhoto(null),
                                        style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error)),
                                        child: const Text('Remove'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    if (_fullMember?.idDocumentBase64 != null) ...[
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
                                                base64Decode(_fullMember!.idDocumentBase64!),
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ),
                                        child: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.grey.shade300),
                                            image: DecorationImage(
                                              image: MemoryImage(base64Decode(_fullMember!.idDocumentBase64!)),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    Expanded(
                                      child: Text(
                                        _fullMember?.idDocumentBase64 != null
                                            ? 'ID: ${_fullMember!.idDocumentType ?? 'Uploaded'}'
                                            : 'Identity document',
                                        style: GoogleFonts.poppins(fontSize: 14, color: AppTheme.onSurface),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: () async {
                                        final pair = await _pickIdDocument();
                                        if (pair != null) await _updateIdDocument(pair.$1, pair.$2);
                                      },
                                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary.withOpacity(0.15), foregroundColor: AppTheme.primary),
                                      child: Text(_fullMember?.idDocumentBase64 != null && _fullMember!.idDocumentBase64!.isNotEmpty ? 'Re-upload' : 'Upload'),
                                    ),
                                    if (_fullMember?.idDocumentBase64 != null && _fullMember!.idDocumentBase64!.isNotEmpty)
                                      OutlinedButton(
                                        onPressed: () => _updateIdDocument(null, null),
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
              const SizedBox(height: 20),
              if (!isActive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 20, color: Colors.orange.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Check-in and check-out are disabled for inactive or cancelled membership.',
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Inbox, Check In, Check Out – for viewing due fees and marking entry/exit
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (_inboxKey.currentContext != null) {
                          Scrollable.ensureVisible(
                            _inboxKey.currentContext!,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      icon: Icon(Icons.inbox_rounded, size: 20, color: _duePayments.isNotEmpty ? AppTheme.primary : Colors.grey),
                      label: Text(
                        'Inbox',
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: BorderSide(color: _duePayments.isNotEmpty ? AppTheme.primary : Colors.grey),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_checkedInToday || _checkingIn || !isActive) ? null : _checkInSelf,
                      icon: _checkingIn
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                          : Icon(_checkedInToday ? Icons.check_circle : Icons.login, size: 20),
                      label: Text(
                        _checkedInToday ? 'Checked in' : (_checkingIn ? '...' : 'Check In'),
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: AppTheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_checkedOutToday || _checkingOut || !_checkedInToday || !isActive) ? null : _checkOutSelf,
                      icon: _checkingOut
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_checkedOutToday ? Icons.check_circle : Icons.logout, size: 20),
                      label: Text(
                        _checkedOutToday ? 'Checked out' : (_checkingOut ? '...' : 'Check Out'),
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ambientFloat(
                order: 3,
                child: _animatedReveal(
                order: 2,
                child: _buildInboxSection(context, padding, radius, _inboxKey),
              ),
              ),
              const SizedBox(height: 24),
              _ambientFloat(
                order: 4,
                child: _animatedReveal(
                order: 3,
                child: _buildPaymentHistorySection(context, padding, radius),
              ),
              ),
              const SizedBox(height: 24),
              Text('Attendance', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
              const SizedBox(height: 8),
              _ambientFloat(
                order: 5,
                child: _animatedReveal(
                order: 4,
                child: AttendanceStatsWidget(
                totalVisits: _attendanceStats?['total_visits'] ?? 0,
                visitsThisMonth: _attendanceStats?['visits_this_month'] ?? 0,
                avgDurationMinutes: _attendanceStats?['avg_duration_minutes'],
                lastVisit: lastAttendance.isEmpty ? '-' : lastAttendance,
                isLoading: _loadingStats,
              ),
              ),
              ),
              const SizedBox(height: 24),
              if (_isPT) ...[
                if (workoutSchedule.isNotEmpty) ...[
                  Text('Workout Schedule', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                  const SizedBox(height: 8),
                  Card(
                    color: AppTheme.surfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
                    child: Padding(
                      padding: EdgeInsets.all(padding),
                      child: SelectableText(workoutSchedule, style: GoogleFonts.poppins(color: AppTheme.onSurface)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (dietChart.isNotEmpty) ...[
                  Text('Diet Chart', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                  const SizedBox(height: 8),
                  Card(
                    color: AppTheme.surfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
                    child: Padding(
                      padding: EdgeInsets.all(padding),
                      child: SelectableText(dietChart, style: GoogleFonts.poppins(color: AppTheme.onSurface)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                if (workoutSchedule.isEmpty && dietChart.isEmpty)
                  Text('No schedule or diet assigned yet.', style: GoogleFonts.poppins(color: Colors.grey)),
              ] else ...[
                Text('Preset Weekly Workouts', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: ['Chest Day', 'Leg Day', 'Back Day', 'Shoulder Day', 'Arm Day', 'Full Body'].map((preset) {
                    return ActionChip(
                      label: Text(preset),
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected: $preset'))),
                      backgroundColor: AppTheme.primary.withOpacity(0.2),
                      side: const BorderSide(color: AppTheme.primary),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
        ),
        ],
      ),
    ),
    );
  }

  Widget _buildPaymentHistorySection(BuildContext context, double padding, double radius) {
    return _LuxuryCard(
      padding: EdgeInsets.all(padding),
      borderRadius: BorderRadius.circular(radius),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _breathingHighlight(
              child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFD4AF37).withOpacity(0.22),
                    const Color(0xFFF5E6A3).withOpacity(0.10),
                  ],
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final countText = '${_paymentHistory.isNotEmpty ? _paymentHistory.length : _paidPayments.length} record(s)';
                  if (constraints.maxWidth < 260) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.receipt_long_rounded, color: Color(0xFFB68A10), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Payment history',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          countText,
                          style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.onSurfaceVariant),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, color: Color(0xFFB68A10), size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Payment history',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        countText,
                        style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.onSurfaceVariant),
                      ),
                    ],
                  );
                },
              ),
            ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: Column(
                key: ValueKey('${_loadingPaymentHistory}_${_paymentHistory.length}_${_paidPayments.length}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadingPaymentHistory)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      ),
                    )
                  else if (_paymentHistory.isEmpty && _paidPayments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No payment history yet.',
                        style: GoogleFonts.poppins(color: AppTheme.onSurfaceVariant, fontSize: 14),
                      ),
                    )
                  else if (_paymentHistory.isEmpty)
                    ..._paidPayments.map((p) {
                      final paidAt = p['paid_at']?.toString();
                      final paidDate = paidAt != null && paidAt.isNotEmpty
                          ? formatDisplayDate(DateTime.tryParse(paidAt))
                          : '—';
                      final feeType = (p['fee_type'] as String?) ?? 'Payment';
                      final amount = p['amount'] ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  feeType,
                                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.onSurface),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₹$amount',
                                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary),
                                  ),
                                  Text(
                                    'Received: $paidDate',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    })
                  else
                    ..._paymentHistory.map((inv) {
                      final paidDateStr = inv.paidAt != null ? formatDisplayDate(inv.paidAt) : '—';
                      final billNo = inv.billNumber ?? '#${inv.id.length >= 8 ? inv.id.substring(0, 8) : inv.id}';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    billNo,
                                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                                  ),
                                  Text(
                                    'Received: $paidDateStr',
                    style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFFB68A10)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...inv.items.map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.description,
                                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700),
                                          ),
                                        ),
                                        Text(
                                          '₹${item.amount}',
                                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  )),
                              const Divider(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Total', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                                  Text(
                                    '₹${inv.total}',
                                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  if (context.mounted) {
                                    await PdfInvoiceHelper.generateAndPrint(inv.toJson());
                                  }
                                },
                                icon: const Icon(Icons.print_rounded, size: 18),
                                label: const Text('Print invoice PDF'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildInboxSection(BuildContext context, double padding, double radius, [GlobalKey? scrollKey]) {
    return Container(
      key: scrollKey,
      child: _LuxuryCard(
        padding: EdgeInsets.all(padding),
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inbox_rounded, color: AppTheme.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inbox', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                      Text('Due fees & reminders', style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            if (_hasOverdue) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active, size: 20, color: AppTheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pay your dues to avoid interruption.',
                        style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.error, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_loadingPayments)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppTheme.primary)))
            else if (_duePayments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "No pending fees. You're all set.",
                  style: GoogleFonts.poppins(color: AppTheme.onSurfaceVariant, fontSize: 14),
                ),
              )
            else
              ...List.generate(_duePayments.length, (i) {
                final map = _duePayments[i];
                return Padding(
                  padding: EdgeInsets.only(bottom: i < _duePayments.length - 1 ? 8 : 0),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${map['fee_type']} • ₹${map['amount']}', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
                    subtitle: Text(map['status'] as String? ?? '', style: TextStyle(color: map['status'] == 'Overdue' ? AppTheme.error : AppTheme.primary, fontSize: 12)),
                    trailing: FilledButton(
                      onPressed: () => _showPayDialog(map),
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
                      child: const Text('Pay'),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _showPayDialog(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        title: Text('Pay ₹${payment['amount']}', style: GoogleFonts.poppins(color: AppTheme.primary)),
        content: Text('Simulated payment (Razorpay/Stripe). Confirm to mark as paid.', style: GoogleFonts.poppins(color: AppTheme.onSurface)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final mid = widget.member.id;
              final pid = payment['id'] as String?;
              if (mid.isEmpty || pid == null) return;
              try {
                final r = await ApiClient.instance.post('/payments/pay?member_id=$mid&payment_id=$pid');
                if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment recorded successfully!')));
                  _loadPayments();
                }
              } catch (_) {}
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class _UploadPreviewTile extends StatefulWidget {
  final String title;
  final Widget preview;
  final VoidCallback onChange;
  final VoidCallback? onRemove;

  const _UploadPreviewTile({
    required this.title,
    required this.preview,
    required this.onChange,
    this.onRemove,
  });

  @override
  State<_UploadPreviewTile> createState() => _UploadPreviewTileState();
}

class _UploadPreviewTileState extends State<_UploadPreviewTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 3.6,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.35)),
                    color: Colors.white.withOpacity(0.76),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Center(child: widget.preview),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _hovered ? 1 : 0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.black.withOpacity(0.34),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Change',
                          onPressed: widget.onChange,
                          icon: const Icon(Icons.edit, color: Colors.white),
                        ),
                        if (widget.onRemove != null)
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: widget.onRemove,
                            icon: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AttendanceStatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.76),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFB68A10)),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _LuxuryCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  const _LuxuryCard({
    required this.child,
    required this.padding,
    required this.borderRadius,
    this.onTap,
  });

  @override
  State<_LuxuryCard> createState() => _LuxuryCardState();
}

class _LuxuryCardState extends State<_LuxuryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withOpacity(_hovered ? 0.24 : 0.12),
              blurRadius: _hovered ? 20 : 12,
              spreadRadius: _hovered ? 1 : 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Material(
              color: const Color(0xCCFFFFFF),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: widget.borderRadius,
                splashColor: const Color(0xFFD4AF37).withOpacity(0.14),
                hoverColor: const Color(0xFFD4AF37).withOpacity(0.06),
                child: Padding(
                  padding: widget.padding,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
