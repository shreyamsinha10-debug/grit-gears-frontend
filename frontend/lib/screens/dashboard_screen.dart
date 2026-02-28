// ---------------------------------------------------------------------------
// Members dashboard – list/search members, add, edit, view detail, check-in.
// ---------------------------------------------------------------------------
// Shown in Admin Dashboard "Members" tab. Fetches members from API, shows
// [Member] list with search; tap opens [MemberDetailScreen]. Also used for
// quick check-in from list. Defines local [Member] model for UI.
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_fade.dart';
import '../widgets/skeleton_loading.dart';
import 'attendance_report_screen.dart';

// ---------------------------------------------------------------------------
// Session-level avatar cache — each photo is fetched at most once per session.
// Key: member ID, Value: decoded JPEG/PNG bytes (null = no photo).
// ---------------------------------------------------------------------------
final Map<String, Uint8List?> _avatarCache = {};

/// Lazily loads and caches a member's profile photo.
/// Shows the initial-letter placeholder until the photo arrives.
class _MemberAvatarWidget extends StatefulWidget {
  final String memberId;
  final String memberName;
  const _MemberAvatarWidget({required this.memberId, required this.memberName});

  @override
  State<_MemberAvatarWidget> createState() => _MemberAvatarWidgetState();
}

class _MemberAvatarWidgetState extends State<_MemberAvatarWidget> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    if (_avatarCache.containsKey(widget.memberId)) {
      _bytes = _avatarCache[widget.memberId];
    } else {
      _fetchAvatar();
    }
  }

  Future<void> _fetchAvatar() async {
    try {
      final r = await ApiClient.instance.get('/members/${widget.memberId}/photo', useCache: false);
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final b64 = data['photo_base64'] as String?;
        final bytes = b64 != null && b64.isNotEmpty ? base64Decode(b64) : null;
        _avatarCache[widget.memberId] = bytes;
        if (mounted) setState(() => _bytes = bytes);
        return;
      }
    } catch (_) {}
    _avatarCache[widget.memberId] = null;
  }

  @override
  Widget build(BuildContext context) {
    final initial = (widget.memberName.isNotEmpty ? widget.memberName[0] : '?').toUpperCase();
    return CircleAvatar(
      radius: 22,
      backgroundColor: AppTheme.primary.withOpacity(0.2),
      foregroundColor: AppTheme.primary,
      backgroundImage: _bytes != null ? MemoryImage(_bytes!) : null,
      child: _bytes == null
          ? Text(initial, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
          : null,
    );
  }
}

class Member {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String membershipType;
  final String batch;
  final String status;
  final String? address;
  final String? dateOfBirth;  // YYYY-MM-DD from API
  final String? gender;
  final String? workoutSchedule;
  final String? dietChart;
  final String? photoBase64;
  final String? idDocumentBase64;
  final String? idDocumentType;  // Aadhar, Driving Licence, Voter ID, Passport
  final DateTime? createdAt;
  final DateTime? lastAttendanceDate;
  final bool? isCheckedInToday;
  final bool? isCheckedOutToday;

  Member({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.membershipType,
    required this.batch,
    required this.status,
    this.address,
    this.dateOfBirth,
    this.gender,
    this.workoutSchedule,
    this.dietChart,
    this.photoBase64,
    this.idDocumentBase64,
    this.idDocumentType,
    this.createdAt,
    this.lastAttendanceDate,
    this.isCheckedInToday,
    this.isCheckedOutToday,
  });

  factory Member.fromJson(Map<String, dynamic> json) {
    final createdAt = parseApiDateTime(json['created_at']?.toString());
    final lastAttendanceDate = parseApiDate(json['last_attendance_date']?.toString());
    
    bool? isCheckedIn;
    bool? isCheckedOut;
    try {
      final todayStatus = json['today_status'] as Map<String, dynamic>?;
      if (todayStatus != null) {
        isCheckedIn = todayStatus['checked_in'] as bool?;
        isCheckedOut = todayStatus['checked_out'] as bool?;
      }
    } catch (_) {}

    return Member(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      membershipType: json['membership_type'] as String? ?? '',
      batch: json['batch'] as String? ?? '',
      status: json['status'] as String? ?? 'Active',
      address: json['address'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      gender: json['gender'] as String?,
      workoutSchedule: json['workout_schedule'] as String?,
      dietChart: json['diet_chart'] as String?,
      photoBase64: json['photo_base64'] as String?,
      idDocumentBase64: json['id_document_base64'] as String?,
      idDocumentType: json['id_document_type'] as String?,
      createdAt: createdAt,
      lastAttendanceDate: lastAttendanceDate,
      isCheckedInToday: isCheckedIn,
      isCheckedOutToday: isCheckedOut,
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final bool isEmbedded;
  final String? searchQuery;
  final void Function(Member member)? onMemberTap;

  const DashboardScreen({super.key, this.isEmbedded = false, this.searchQuery, this.onMemberTap});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Member> _members = [];
  bool _loading = true;
  String? _error;
  final Set<String> _checkingInIds = {};
  final Set<String> _checkingOutIds = {};
  bool _runningAdminAction = false;

  List<Member> get _filteredMembers {
    final q = widget.searchQuery?.trim().toLowerCase();
    if (q == null || q.isEmpty) return _members;
    return _members.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  static const int _pageSize = 50;
  int _skip = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  Future<void> _loadMembers({bool append = false}) async {
    if (!append) {
      setState(() { _loading = true; _error = null; _skip = 0; _hasMore = true; });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final response = await ApiClient.instance.get(
        '/members',
        queryParameters: {'brief': 'true', 'include_avatar': 'false', 'skip': '$_skip', 'limit': '$_pageSize'},
        useCache: !append,
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final list = jsonDecode(response.body) as List<dynamic>;
        final newMembers = list.map((e) => Member.fromJson(e as Map<String, dynamic>)).toList();
        setState(() {
          if (append) {
            _members = [..._members, ...newMembers];
            _loadingMore = false;
          } else {
            _members = newMembers;
            _loading = false;
            _error = null;
          }
          _skip += newMembers.length;
          _hasMore = newMembers.length >= _pageSize;
        });
      } else {
        setState(() {
          _error = 'Failed to load members';
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final isTimeout = msg.contains('TimeoutException') || msg.contains('timed out');
      setState(() {
        _error = isTimeout
            ? 'Request timed out. Check your connection and that the server is running.'
            : msg.split('\n').first;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _checkOut(Member m) async {
    if (_checkingOutIds.contains(m.id)) return;
    setState(() => _checkingOutIds.add(m.id));
    try {
      final response = await ApiClient.instance.post('/attendance/check-out/${m.id}');
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        hapticSuccess();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checked out')));
        _loadMembers(append: false);
      } else {
        final body = jsonDecode(response.body) as Map<String, dynamic>?;
        final detail = body?['detail']?.toString() ?? 'Check-out failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().split('\n').first}')));
    } finally {
      if (mounted) setState(() => _checkingOutIds.remove(m.id));
    }
  }

  Future<void> _checkIn(Member m) async {
    if (_checkingInIds.contains(m.id)) return;
    setState(() => _checkingInIds.add(m.id));

    try {
      final response = await ApiClient.instance
          .post('/attendance/check-in/${m.id}')
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Request timed out. Check your connection.');
      });

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        String batchLabel = 'Unknown';
        if (response.body.isNotEmpty) {
          try {
            final body = jsonDecode(response.body) as Map<String, dynamic>?;
            batchLabel = body?['batch'] as String? ?? batchLabel;
          } catch (_) {}
        }
        if (!mounted) return;
        hapticSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.onPrimary, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text('Checked in for $batchLabel Batch!')),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        _loadMembers(append: false);
      } else {
        String detail = 'Check-in failed';
        if (response.body.isNotEmpty) {
          try {
            final body = jsonDecode(response.body) as Map<String, dynamic>?;
            final d = body?['detail'];
            detail = d is String ? d : (d?.toString() ?? detail);
          } catch (_) {}
        }
        detail = '${detail.trim()} (${response.statusCode})';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppTheme.onPrimary, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(detail)),
              ],
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().split('\n').first.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Check-in failed: $msg'),
              const SizedBox(height: 6),
              const Text(
                'Tap Refresh to reload. If the server received the request, check Today\'s Attendance.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Refresh',
            onPressed: () => _loadMembers(append: false),
            textColor: AppTheme.onSurface,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _checkingInIds.remove(m.id));
    }
  }

  Future<void> _showMemberEditDialog(BuildContext context, Member m) async {
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
    if (m.batch.isNotEmpty && !batchNames.contains(m.batch)) batchNames.insert(0, m.batch);
    if (batchNames.isEmpty) batchNames = ['Morning', 'Evening', 'Ladies'];

    if (!context.mounted) return;

    final nameController = TextEditingController(text: m.name);
    final phoneController = TextEditingController(text: m.phone);
    final emailController = TextEditingController(text: m.email);
    String batch = batchNames.contains(m.batch) ? m.batch : batchNames.first;
    String status = m.status;
    String membershipType = m.membershipType;
    final scheduleController = TextEditingController(text: m.workoutSchedule ?? '');
    final dietController = TextEditingController(text: m.dietChart ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
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
                DropdownButtonFormField<String>(
                  value: membershipType,
                  decoration: const InputDecoration(labelText: 'Membership type'),
                  items: const [
                    DropdownMenuItem(value: 'Regular', child: Text('Regular')),
                    DropdownMenuItem(value: 'PT', child: Text('PT')),
                  ],
                  onChanged: (v) => setState(() => membershipType = v ?? membershipType),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: batch,
                  decoration: const InputDecoration(labelText: 'Batch'),
                  items: batchNames
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) => setState(() => batch = v ?? batch),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'Active', child: Text('Active')),
                    DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => setState(() => status = v ?? status),
                ),
                if (membershipType.toLowerCase() == 'pt') ...[
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
                Navigator.pop(ctx);
                final body = <String, dynamic>{
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'email': emailController.text.trim(),
                  'batch': batch,
                  'status': status,
                  'membership_type': membershipType,
                };
                if (membershipType.toLowerCase() == 'pt') {
                  body['workout_schedule'] = scheduleController.text;
                  body['diet_chart'] = dietController.text;
                }
                try {
                  final r = await ApiClient.instance.patch(
                    '/members/${m.id}',
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  );
                  if (!mounted) return;
                  if (r.statusCode >= 200 && r.statusCode < 300) {
                    _loadMembers();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member updated')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${r.body}')));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPTEditSheet(BuildContext context, Member m) {
    final scheduleController = TextEditingController(text: m.workoutSchedule ?? '');
    final dietController = TextEditingController(text: m.dietChart ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit PT: ${m.name}', style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: scheduleController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Workout Schedule',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dietController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Diet Chart',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  try {
                    final r = await ApiClient.instance.patch(
                      '/members/${m.id}',
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'workout_schedule': scheduleController.text,
                        'diet_chart': dietController.text,
                      }),
                    );
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    if (r.statusCode >= 200 && r.statusCode < 300) {
                      _loadMembers();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PT details updated')));
                    }
                  } catch (_) {}
                },
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _seedInactiveTest() async {
    if (_runningAdminAction) return;
    setState(() => _runningAdminAction = true);
    try {
      final response = await ApiClient.instance.post('/admin/seed-inactive-test');
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _loadMembers();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Created 2 test members (last check-in 91 days ago). Tap menu → Mark inactive (90d) to test.'),
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Seed failed: ${response.statusCode}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().split('\n').first}')));
    } finally {
      if (mounted) setState(() => _runningAdminAction = false);
    }
  }

  Future<void> _markInactiveByAttendance() async {
    if (_runningAdminAction) return;
    setState(() => _runningAdminAction = true);
    try {
      final response = await ApiClient.instance.post('/admin/mark-inactive-by-attendance');
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>?;
        final count = body?['updated_count'] as int? ?? 0;
        _loadMembers();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count member(s) marked Inactive (no check-in for 90+ days).')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mark inactive failed: ${response.statusCode}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().split('\n').first}')));
    } finally {
      if (mounted) setState(() => _runningAdminAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildBody(context);
    if (widget.isEmbedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Today\'s Attendance',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AttendanceReportScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _loadMembers(append: false),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '90-day automation test',
            onSelected: (value) {
              if (value == 'seed') _seedInactiveTest();
              if (value == 'mark') _markInactiveByAttendance();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'seed', child: Text('Seed 90-day test data')),
              const PopupMenuItem(value: 'mark', child: Text('Mark inactive (90d)')),
            ],
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return _loading
        ? const Padding(
            padding: EdgeInsets.all(16),
            child: SkeletonMemberList(itemCount: 8),
          )
        : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => _loadMembers(append: false),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
                        ),
                      ],
                    ),
                  ),
                )
              : _filteredMembers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade600),
                          const SizedBox(height: 16),
                          Text(
                            widget.searchQuery != null ? 'No members match your search' : 'No members yet',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.searchQuery != null ? 'Try a different name' : 'Register members from the home screen',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () {
                        ApiClient.instance.invalidateCache();
                        return _loadMembers(append: false);
                      },
                      color: AppTheme.primary,
                      child: ListView.builder(
                        padding: EdgeInsets.all(LayoutConstants.screenPadding(context)),
                        itemCount: _filteredMembers.length + (_hasMore ? 1 : 0) + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _filteredMembers.length) {
                            if (_loadingMore) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Center(
                                child: TextButton.icon(
                                  onPressed: () => _loadMembers(append: true),
                                  icon: const Icon(Icons.add_circle_outline, size: 20),
                                  label: const Text('Load more'),
                                ),
                              ),
                            );
                          }
                          final m = _filteredMembers[index];
                          final isActive = m.status.toLowerCase() == 'active';
                          final isCheckingIn = _checkingInIds.contains(m.id);
                          final isCheckingOut = _checkingOutIds.contains(m.id);
                          final radius = LayoutConstants.cardRadius(context);
                          return FadeInSlide(
                            child: RepaintBoundary(
                              child: InkWell(
                                onTap: widget.onMemberTap != null ? () => widget.onMemberTap!(m) : null,
                                borderRadius: BorderRadius.circular(radius),
                                child: Card(
                            color: AppTheme.surfaceVariant,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(radius),
                              side: BorderSide(
                                color: isActive ? AppTheme.primary.withOpacity(0.5) : AppTheme.outline,
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _MemberAvatarWidget(memberId: m.id, memberName: m.name),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: isActive ? AppTheme.success : Colors.grey.shade400,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    m.name,
                                                    style: TextStyle(color: AppTheme.onSurface, fontWeight: FontWeight.w600, fontSize: 15),
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              m.email,
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                            Text(
                                              m.phone,
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                _chip(m.membershipType, AppTheme.primary),
                                                _chip(m.batch, Colors.grey.shade600),
                                                _chip(m.status, isActive ? AppTheme.success : Colors.grey),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () => _showMemberEditDialog(context, m),
                                        style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 12), foregroundColor: AppTheme.onSurface),
                                        child: const Text('Edit'),
                                      ),
                                      if (m.membershipType.toLowerCase() == 'pt')
                                        TextButton(
                                          onPressed: () => _showPTEditSheet(context, m),
                                          style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8), foregroundColor: AppTheme.primary),
                                          child: const Text('PT'),
                                        ),
                                      if (m.isCheckedOutToday == true)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.success.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppTheme.success),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle, size: 16, color: AppTheme.success),
                                              const SizedBox(width: 4),
                                              Text('Checked Out', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 13)),
                                            ],
                                          ),
                                        )
                                      else if (m.isCheckedInToday == true)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: AppTheme.success.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: AppTheme.success),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.check_circle, size: 16, color: AppTheme.success),
                                                  const SizedBox(width: 4),
                                                  Text('Checked In', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            OutlinedButton(
                                              onPressed: (isCheckingOut || !isActive) ? null : () => _checkOut(m),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: AppTheme.primary,
                                                side: const BorderSide(color: AppTheme.primary),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                minimumSize: Size.zero,
                                              ),
                                              child: isCheckingOut
                                                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                                                  : const Text('Check-Out'),
                                            ),
                                          ],
                                        )
                                      else
                                        FilledButton.icon(
                                          onPressed: (isCheckingIn || !isActive) ? null : () => _checkIn(m),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppTheme.primary,
                                            foregroundColor: AppTheme.onPrimary,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            minimumSize: Size.zero,
                                          ),
                                          icon: isCheckingIn
                                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                                              : const Icon(Icons.login, size: 18),
                                          label: const Text('Check-In'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            ),
                          ),
                        ),
                        );
                        },  // itemBuilder
                      ),
                    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}
