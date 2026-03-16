// ---------------------------------------------------------------------------
// Admin dashboard – bottom nav: Members, Attendance, Billing, More.
// ---------------------------------------------------------------------------
// Hosts tabs for member list, attendance report, billing/invoices, and
// "More" (analytics, export, registration, fee reminders, settings).
// Session timeout (e.g. 15 min) and theme toggle. Uses [ApiClient] for all API calls.
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../core/export_helper.dart';
import '../core/secure_storage.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'attendance_report_screen.dart';
import 'heatmap_screen.dart';
import 'billing_screen.dart';
import 'dashboard_screen.dart';
import 'gym_settings_screen.dart';
import 'member_detail_screen.dart';
import 'registration_screen.dart';
import 'broadcast_messages_screen.dart';
import 'expense_management_screen.dart';
import 'retention_alerts_screen.dart';

/// Breakpoint below which overview cards stack vertically (avoid overflow on phones).
const double _overviewNarrowBreakpoint = 420;

const _padding = 20.0;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  int _membersRefreshKey = 0;
  final Set<int> _visitedTabs = {0};
  DateTime _lastActivityAt = DateTime.now();
  Timer? _sessionTimer;
  static const Duration _sessionTimeout = Duration(minutes: 15);

  Map<String, dynamic>? _gymProfile;

  @override
  void initState() {
    super.initState();
    _loadGymProfile();
    _sessionTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().difference(_lastActivityAt) > _sessionTimeout) {
        _sessionTimer?.cancel();
        _sessionTimer = null;
        ApiClient.setAuthToken(null);
        SecureStorage.setAuthToken(null);
        SecureStorage.setAuthRole(null);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired. Please log in again.')),
        );
      }
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }

  void _onActivity() {
    _lastActivityAt = DateTime.now();
  }

  Future<void> _loadGymProfile() async {
    try {
      final r = await ApiClient.instance.get('/gym/profile', useCache: true);
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        setState(() => _gymProfile = jsonDecode(r.body) as Map<String, dynamic>?);
      }
    } catch (_) {}
  }

  Widget _defaultLogoWidget({double? size}) {
    final s = size ?? 32.0;
    return Image.asset(
      defaultLogoAsset,
      height: s,
      width: s,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.fitness_center, color: AppTheme.primary, size: s * 0.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _gymProfile;
    final String displayName = (profile != null && (profile['name'] as String?)?.trim().isNotEmpty == true)
        ? (profile['name'] as String).trim()
        : defaultGymName;
    final bool hasCustomLogo = profile != null && (profile['logo_base64'] as String?)?.trim().isNotEmpty == true;
    // Larger logo on narrow (mobile) screens for better visibility.
    final double logoSize = MediaQuery.sizeOf(context).width < 600 ? 44 : 32;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Back button: go to home (Overview) tab instead of exiting; logout is via dedicated button only.
        if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasCustomLogo)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(profile['logo_base64'] as String),
                  height: logoSize,
                  width: logoSize,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _defaultLogoWidget(size: logoSize),
                ),
              )
            else
              _defaultLogoWidget(size: logoSize),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$displayName Admin',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(FontAwesomeIcons.bullhorn),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastMessagesScreen())),
            tooltip: 'Broadcast Messages',
          ),
          IconButton(
            icon: const Icon(FontAwesomeIcons.chartSimple),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeatmapScreen())),
            tooltip: 'Occupancy heatmap',
          ),
          IconButton(
            icon: const Icon(FontAwesomeIcons.calendarDays),
            tooltip: 'Attendance report',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceReportScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            tooltip: 'P&L / Expenses',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseManagementScreen())),
          ),
          Tooltip(
            message: 'Retention Alerts',
            child: IconButton(
              icon: const Icon(Icons.warning_amber_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RetentionAlertsScreen())),
            ),
          ),
          IconButton(
            icon: const Icon(FontAwesomeIcons.fileExport),
            tooltip: 'Export data (members, payments, billing)',
            onPressed: _showExportMenu,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => LoginScreen.logout(context),
          ),
        ],
      ),
      body: Listener(
        onPointerDown: (_) => _onActivity(),
        behavior: HitTestBehavior.translucent,
        child: Padding(
          padding: EdgeInsets.all(LayoutConstants.screenPadding(context)),
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              _visitedTabs.contains(0) ? _OverviewTab(isActive: _selectedIndex == 0) : const SizedBox.shrink(),
              _visitedTabs.contains(1)
                  ? _MembersTab(
                      refreshKey: _membersRefreshKey,
                      onRegisterPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationScreen()));
                        setState(() => _membersRefreshKey++);
                      },
                      onImportPressed: _importMembers,
                      onMemberTap: (m) => Navigator.push(context, MaterialPageRoute(builder: (_) => MemberDetailScreen(member: m))).then((_) => setState(() => _membersRefreshKey++)),
                    )
                  : const SizedBox.shrink(),
              _visitedTabs.contains(2) ? _FeesTab(isActive: _selectedIndex == 2) : const SizedBox.shrink(),
              _visitedTabs.contains(3) ? const _BillingTab() : const SizedBox.shrink(),
              _visitedTabs.contains(4) ? GymSettingsScreen(embedded: true, onSaved: _loadGymProfile) : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          setState(() {
            _selectedIndex = i;
            _visitedTabs.add(i);
            if (i == 1) _membersRefreshKey++;
          });
          _onActivity();
        },
        backgroundColor: AppTheme.surfaceVariant,
        indicatorColor: AppTheme.primary,
        destinations: const [
          NavigationDestination(icon: Icon(FontAwesomeIcons.chartPie), label: 'Overview'),
          NavigationDestination(icon: Icon(FontAwesomeIcons.users), label: 'Members'),
          NavigationDestination(icon: Icon(FontAwesomeIcons.indianRupeeSign), label: 'Fees'),
          NavigationDestination(icon: Icon(FontAwesomeIcons.fileInvoiceDollar), label: 'Billing'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    ),
    );
  }

  void _showExportMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(_padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(FontAwesomeIcons.users, color: AppTheme.primary),
                title: const Text('Export Members to Excel'),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadExport('/export/members', 'members.xlsx');
                },
              ),
              ListTile(
                leading: const Icon(FontAwesomeIcons.fileInvoiceDollar, color: AppTheme.primary),
                title: const Text('Export Payments to Excel'),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadExport('/export/payments', 'payments.xlsx');
                },
              ),
              ListTile(
                leading: const Icon(FontAwesomeIcons.fileExport, color: AppTheme.primary),
                title: const Text('Export Billing to Excel'),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadExport('/export/billing', 'billing_history.xlsx');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadExport(String path, String filename) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exporting $filename...')),
    );
    final savedPath = await saveExportToDownloads(path, filename);
    if (!context.mounted) return;
    if (savedPath != null) {
      final label = await exportLocationLabel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to $label'),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed. Check connection and try again.')),
      );
    }
  }

  Future<void> _importMembers() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final path = file.path;
    final name = file.name;
    final bytes = file.bytes;
    if ((path == null || path.isEmpty) && (bytes == null || bytes.isEmpty)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected file. Try again.')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);

    scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Importing members…'), duration: Duration(seconds: 2)));

    // Show progress dialog immediately so user sees something is happening
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.primary),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Importing members…',
                  style: GoogleFonts.poppins(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Let the dialog render before starting the upload
    await Future.delayed(const Duration(milliseconds: 350));

    try {
      final response = await ApiClient.instance.postMultipart(
        '/members/import',
        fileField: 'file',
        filePath: path,
        fileBytes: bytes,
        filename: name,
      );
      if (!context.mounted) return;
      navigator.pop();

      Map<String, dynamic>? body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>?;
      } catch (_) {
        body = null;
      }

      if (response.statusCode >= 200 && response.statusCode < 300 && body != null) {
        final created = body['created'] as int? ?? 0;
        final updated = body['updated'] as int? ?? 0;
        final errors = body['errors'] as List<dynamic>? ?? [];
        setState(() => _membersRefreshKey++);

        final String resultMsg;
        if (errors.isEmpty) {
          resultMsg = 'Created: $created\nUpdated: $updated';
        } else {
          final buffer = StringBuffer();
          buffer.writeln('Created: $created\nUpdated: $updated');
          buffer.writeln();
          buffer.writeln('${errors.length} row(s) had errors:');
          for (final e in errors) {
            final row = e is Map ? e['row']?.toString() : '';
            final message = e is Map ? e['message']?.toString() ?? '' : e.toString();
            buffer.writeln('• Row $row: $message');
          }
          resultMsg = buffer.toString();
        }

        await showDialog<void>(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: Text('Import complete', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: SingleChildScrollView(
              child: Text(resultMsg, style: GoogleFonts.poppins(fontSize: 14)),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        final detail = body?['detail'] ?? response.body;
        await showDialog<void>(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: Text('Import failed', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red.shade700)),
            content: SingleChildScrollView(
              child: Text(
                detail is String ? detail : detail.toString(),
                style: GoogleFonts.poppins(fontSize: 14),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      navigator.pop();
      final errorMsg = e.toString().split('\n').first;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: Text('Import failed', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red.shade700)),
          content: SingleChildScrollView(
            child: Text(
              errorMsg,
              style: GoogleFonts.poppins(fontSize: 14),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      // Also show snackbar so user definitely sees feedback
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Import failed: $errorMsg'), duration: const Duration(seconds: 4)));
    }
  }
}

class _BillingTab extends StatelessWidget {
  const _BillingTab();

  @override
  Widget build(BuildContext context) {
    return const BillingScreen();
  }
}

class _OverviewTab extends StatefulWidget {
  final bool isActive;
  const _OverviewTab({this.isActive = false});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _sendingReminders = false;
  String? _error;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_OverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      Map<String, String>? params;
      if (_dateFrom != null && _dateTo != null) {
        params = {
          'date_from': formatApiDate(_dateFrom!),
          'date_to': formatApiDate(_dateTo!),
        };
      }
      final r = await ApiClient.instance.get('/analytics/dashboard', queryParameters: params, useCache: true);
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        setState(() { _data = jsonDecode(r.body) as Map<String, dynamic>; _loading = false; });
      } else {
        setState(() { _error = 'Failed to load'; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().split('\n').first; _loading = false; });
    }
  }

  Future<void> _pickDateRange() async {
    final from = _dateFrom ?? DateTime.now().subtract(const Duration(days: 30));
    final to = _dateTo ?? DateTime.now();
    final pickedFrom = await showDatePicker(context: context, initialDate: from, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (pickedFrom == null || !mounted) return;
    final pickedTo = await showDatePicker(context: context, initialDate: to.isAfter(pickedFrom) ? to : pickedFrom, firstDate: pickedFrom, lastDate: DateTime.now());
    if (pickedTo == null || !mounted) return;
    setState(() {
      _dateFrom = pickedFrom;
      _dateTo = pickedTo;
    });
    _load();
  }

  void _clearDateRange() {
    setState(() { _dateFrom = null; _dateTo = null; });
    _load();
  }

  Future<void> _sendReminders() async {
    setState(() => _sendingReminders = true);
    try {
      final r = await ApiClient.instance.post('/admin/run-fee-reminders');
      if (mounted) {
        final body = r.statusCode == 200 ? jsonDecode(r.body) as Map<String, dynamic>? : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body?['message']?.toString() ?? 'Done')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send reminders')));
    }
    if (mounted) setState(() => _sendingReminders = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)));
    final d = _data!;
    final padding = LayoutConstants.screenPadding(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 400;
    return RefreshIndicator(
      onRefresh: () {
        ApiClient.instance.invalidateCache();
        return _load();
      },
      color: AppTheme.primary,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(left: padding, right: padding, bottom: padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(FontAwesomeIcons.chartLine, size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today\'s Snapshot',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                      ),
                      Text(
                        formatDisplayDateWithWeekday(DateTime.now()),
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Responsive: 3 cards in a row on wider screens, wrap on narrow
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                if (w < _overviewNarrowBreakpoint) {
                  return Column(
                    children: [
                      _AnalyticsCard(title: 'Check-ins', value: '${d['today_check_ins'] ?? d['today_attendance_count'] ?? 0}', icon: FontAwesomeIcons.rightToBracket, color: AppTheme.success),
                      const SizedBox(height: 12),
                      _AnalyticsCard(title: 'Check-outs', value: '${d['today_check_outs'] ?? 0}', icon: FontAwesomeIcons.rightFromBracket, color: Colors.grey),
                      const SizedBox(height: 12),
                      _AnalyticsCard(title: 'Currently In', value: '${d['today_currently_in'] ?? 0}', icon: FontAwesomeIcons.peopleGroup, color: Colors.blue),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: _AnalyticsCard(title: 'Check-ins', value: '${d['today_check_ins'] ?? d['today_attendance_count'] ?? 0}', icon: FontAwesomeIcons.rightToBracket, color: AppTheme.success)),
                    SizedBox(width: isNarrow ? 8 : 12),
                    Expanded(child: _AnalyticsCard(title: 'Check-outs', value: '${d['today_check_outs'] ?? 0}', icon: FontAwesomeIcons.rightFromBracket, color: Colors.grey)),
                    SizedBox(width: isNarrow ? 8 : 12),
                    Expanded(child: _AnalyticsCard(title: 'Currently In', value: '${d['today_currently_in'] ?? 0}', icon: FontAwesomeIcons.peopleGroup, color: Colors.blue)),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Tooltip(
                  message: 'Select date range for period stats',
                  child: OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(_dateFrom != null && _dateTo != null
                        ? '${_dateFrom!.day}/${_dateFrom!.month} - ${_dateTo!.day}/${_dateTo!.month}'
                        : 'Past period'),
                  ),
                ),
                if (_dateFrom != null && _dateTo != null)
                  IconButton(
                    onPressed: _clearDateRange,
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear date range',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _AnalyticsCard(
                    title: 'Today\'s check-ins',
                    value: '${d['today_attendance_count'] ?? 0}',
                    icon: FontAwesomeIcons.userCheck,
                    color: AppTheme.primary,
                  ),
                ),
                SizedBox(width: isNarrow ? 8 : 16),
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceReportScreen())),
                    borderRadius: BorderRadius.circular(16),
                    child: _AnalyticsCard(
                      title: 'Attendance',
                      value: 'View',
                      icon: FontAwesomeIcons.calendarDays,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeatmapScreen())),
              borderRadius: BorderRadius.circular(16),
              child: _AnalyticsCard(
                title: 'Occupancy heatmap',
                value: 'Busy & quiet times',
                icon: FontAwesomeIcons.chartSimple,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 16),
            if (d['date_from'] != null && d['date_to'] != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _AnalyticsCard(
                      title: 'Attendance (period)',
                      value: '${d['attendance_count_in_range'] ?? 0}',
                      icon: FontAwesomeIcons.userCheck,
                      color: AppTheme.primary,
                    ),
                  ),
                  SizedBox(width: isNarrow ? 8 : 16),
                  Expanded(
                    child: _AnalyticsCard(
                      title: 'Payments received (₹)',
                      value: '${d['payments_received_in_range'] ?? 0}',
                      icon: FontAwesomeIcons.indianRupeeSign,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _AnalyticsCard(title: 'Active Members', value: '${d['active_members'] ?? 0}', icon: FontAwesomeIcons.userCheck, color: AppTheme.success),
            const SizedBox(height: 16),
            _AnalyticsCard(title: 'Inactive Members', value: '${d['inactive_members'] ?? 0}', icon: FontAwesomeIcons.userXmark, color: Colors.grey),
            const SizedBox(height: 16),
            _AnalyticsCard(title: 'Total Collections (₹)', value: '${d['total_collections'] ?? 0}', icon: FontAwesomeIcons.indianRupeeSign, color: AppTheme.primary),
            const SizedBox(height: 16),
            _AnalyticsCard(title: 'Pending Dues (₹)', value: '${d['pending_fees_amount'] ?? 0}', icon: FontAwesomeIcons.clock, color: Colors.orange),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _AnalyticsCard(title: 'Regular', value: '${d['regular_count'] ?? 0}', icon: FontAwesomeIcons.users, color: AppTheme.primary)),
                SizedBox(width: isNarrow ? 8 : 16),
                Expanded(child: _AnalyticsCard(title: 'PT', value: '${d['pt_count'] ?? 0}', icon: FontAwesomeIcons.dumbbell, color: AppTheme.primary)),
              ],
            ),
            const SizedBox(height: 24),
            Tooltip(
              message: 'Send WhatsApp payment reminders to members with due or overdue fees',
              child: FilledButton.icon(
                onPressed: _sendingReminders ? null : _sendReminders,
                icon: _sendingReminders ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(FontAwesomeIcons.whatsapp),
                label: Text(_sendingReminders ? 'Sending...' : 'Send Payment Reminders'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _AnalyticsCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        // When card is in a 3-column row it gets ~1/3 screen; use compact layout to avoid overflow.
        final veryTight = cardWidth > 0 && cardWidth < 160;
        final tight = cardWidth > 0 && cardWidth < 200;
        final pad = LayoutConstants.screenPadding(context);
        final cardPad = veryTight ? 6.0 : (tight ? 8.0 : (cardWidth < 400 ? 12.0 : pad));
        final iconPad = veryTight ? 4.0 : (tight ? 6.0 : 8.0);
        final iconSize = veryTight ? 16.0 : (tight ? 20.0 : 28.0);
        final titleSize = veryTight ? 9.0 : (tight ? 10.0 : 14.0);
        final valueSize = veryTight ? 12.0 : (tight ? 16.0 : 24.0);
        final gap = veryTight ? 4.0 : (tight ? 6.0 : 16.0);
        return Card(
          color: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withOpacity(0.5))),
          child: Padding(
            padding: EdgeInsets.all(cardPad),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(iconPad),
                  decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: FaIcon(icon, color: color, size: iconSize),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: titleSize),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: valueSize, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MembersTab extends StatefulWidget {
  final int refreshKey;
  final VoidCallback onRegisterPressed;
  final VoidCallback? onImportPressed;
  final void Function(dynamic member) onMemberTap;

  const _MembersTab({required this.refreshKey, required this.onRegisterPressed, this.onImportPressed, required this.onMemberTap});

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  final _searchController = TextEditingController();
  List<String> _batchNames = const ['All'];
  String _selectedBatch = 'All';
  bool _loadingBatches = false;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    setState(() => _loadingBatches = true);
    try {
      final r = await ApiClient.instance.get('/gym/profile', useCache: true);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final batchList = data['batches'] as List<dynamic>? ?? [];
        final names = batchList
            .map((b) => ((b as Map<String, dynamic>)['name'] as String? ?? '').trim())
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        setState(() {
          _batchNames = ['All', ...names];
          if (!_batchNames.contains(_selectedBatch)) _selectedBatch = 'All';
        });
      } else {
        setState(() => _loadingBatches = false);
      }
    } catch (_) {
      setState(() => _loadingBatches = false);
    } finally {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Treat phones and medium screens as "narrow" so search + batch filter stack vertically.
    // This avoids horizontal overflow on tablets / small laptops.
    final isNarrow = MediaQuery.sizeOf(context).width < 800;
    // On mobile: larger search icon and padding for better visibility and tap target.
    final double searchIconSize = isNarrow ? 24 : 20;
    final EdgeInsets searchPadding = isNarrow
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    return Column(
      children: [
        if (isNarrow)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedBatch,
                      decoration: const InputDecoration(
                        labelText: 'Batches',
                        isDense: false,
                        border: OutlineInputBorder(),
                      ),
                      items: _batchNames
                          .map((n) => DropdownMenuItem<String>(value: n, child: Text(n)))
                          .toList(),
                      onChanged: _loadingBatches
                          ? null
                          : (v) => setState(() => _selectedBatch = v ?? 'All'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                style: GoogleFonts.poppins(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone…',
                  prefixIcon: Icon(Icons.search, size: searchIconSize, color: Colors.grey.shade600),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: searchPadding,
                  isDense: false,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Tooltip(
                message: 'Register a new member',
                child: FilledButton.icon(
                  onPressed: widget.onRegisterPressed,
                  icon: const Icon(FontAwesomeIcons.userPlus, size: 18),
                  label: const Text('Register'),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
                ),
              ),
              if (widget.onImportPressed != null) ...[
                const SizedBox(height: 8),
                Tooltip(
                  message: 'CSV/Excel columns: Full Name, Email address, Phone, E-mail ID, Address, Date of Birth (MM/DD/YYYY), Gender, Membership Type, Batch',
                  child: OutlinedButton.icon(
                    onPressed: widget.onImportPressed,
                    icon: const Icon(FontAwesomeIcons.fileImport, size: 18),
                    label: const Text('Import Members'),
                  ),
                ),
              ],
            ],
          )
        else
          Row(
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _selectedBatch,
                  decoration: const InputDecoration(
                    labelText: 'Batches',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _batchNames
                      .map((n) => DropdownMenuItem<String>(value: n, child: Text(n)))
                      .toList(),
                  onChanged: _loadingBatches
                      ? null
                      : (v) => setState(() => _selectedBatch = v ?? 'All'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or phone…',
                    prefixIcon: Icon(Icons.search, size: searchIconSize, color: Colors.grey.shade600),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: searchPadding,
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Register a new member',
                child: FilledButton.icon(
                  onPressed: widget.onRegisterPressed,
                  icon: const Icon(FontAwesomeIcons.userPlus, size: 18),
                  label: const Text('Register'),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
                ),
              ),
              if (widget.onImportPressed != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'CSV/Excel: Full Name, Email address, Phone, E-mail ID, Address, DOB (MM/DD/YYYY), Gender, Membership Type, Batch',
                  child: OutlinedButton.icon(
                    onPressed: widget.onImportPressed,
                    icon: const Icon(FontAwesomeIcons.fileImport, size: 18),
                    label: const Text('Import Members'),
                  ),
                ),
              ],
            ],
          ),
        const SizedBox(height: 12),
        Expanded(
          child: DashboardScreen(
            key: ValueKey(widget.refreshKey),
            isEmbedded: true,
            batchFilter: _selectedBatch,
            searchQuery: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
            onMemberTap: widget.onMemberTap,
          ),
        ),
      ],
    );
  }
}

class _FeesTab extends StatefulWidget {
  final bool isActive;
  const _FeesTab({this.isActive = false});

  @override
  State<_FeesTab> createState() => _FeesTabState();
}

class _FeesTabState extends State<_FeesTab> {
  Map<String, dynamic>? _summary;
  List<dynamic> _payments = [];
  bool _loading = true;
  /// null = show all; 'Paid' | 'Due' | 'Overdue' = filter by status
  String? _statusFilter;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_FeesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r1 = await ApiClient.instance.get('/payments/fees-summary', useCache: false);
      final r2 = await ApiClient.instance.get('/payments', useCache: false);
      if (!mounted) return;
      if (r1.statusCode >= 200 && r1.statusCode < 300)
        _summary = jsonDecode(r1.body) as Map<String, dynamic>;
      if (r2.statusCode >= 200 && r2.statusCode < 300)
        _payments = jsonDecode(r2.body) as List<dynamic>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    final paid = _summary?['paid'] as Map<String, dynamic>? ?? {};
    final due = _summary?['due'] as Map<String, dynamic>? ?? {};
    final overdue = _summary?['overdue'] as Map<String, dynamic>? ?? {};
    final padding = LayoutConstants.screenPadding(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 400;
    return RefreshIndicator(
      onRefresh: () {
        ApiClient.instance.invalidateCache();
        return _load();
      },
      color: AppTheme.primary,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(left: padding, right: padding, bottom: padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            isNarrow
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                  _FeeChip('Paid', paid['count'] ?? 0, paid['total_amount'] ?? 0, AppTheme.success, isSelected: _statusFilter == 'Paid', onTap: () => setState(() => _statusFilter = _statusFilter == 'Paid' ? null : 'Paid')),
                  _FeeChip('Due', due['count'] ?? 0, due['total_amount'] ?? 0, AppTheme.primary, subtitle: 'Due in 7 days', isSelected: _statusFilter == 'Due', onTap: () => setState(() => _statusFilter = _statusFilter == 'Due' ? null : 'Due')),
                  _FeeChip('Overdue', overdue['count'] ?? 0, overdue['total_amount'] ?? 0, Colors.orange, subtitle: 'Need immediate payment', isSelected: _statusFilter == 'Overdue', onTap: () => setState(() => _statusFilter = _statusFilter == 'Overdue' ? null : 'Overdue')),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _FeeChip(
                          'Paid',
                          paid['count'] ?? 0,
                          paid['total_amount'] ?? 0,
                          AppTheme.success,
                          isSelected: _statusFilter == 'Paid',
                          onTap: () => setState(() => _statusFilter = _statusFilter == 'Paid' ? null : 'Paid'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FeeChip(
                          'Due',
                          due['count'] ?? 0,
                          due['total_amount'] ?? 0,
                          AppTheme.primary,
                          subtitle: 'Due in 7 days',
                          isSelected: _statusFilter == 'Due',
                          onTap: () => setState(() => _statusFilter = _statusFilter == 'Due' ? null : 'Due'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FeeChip(
                          'Overdue',
                          overdue['count'] ?? 0,
                          overdue['total_amount'] ?? 0,
                          Colors.orange,
                          subtitle: 'Need immediate payment',
                          isSelected: _statusFilter == 'Overdue',
                          onTap: () => setState(() => _statusFilter = _statusFilter == 'Overdue' ? null : 'Overdue'),
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 24),
            Text('All Payments', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            if (_statusFilter != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Showing $_statusFilter only. Tap the chip again to show all.',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                filled: true,
                fillColor: AppTheme.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            ...(_payments.where((p) {
              final map = p as Map<String, dynamic>;
              if (_statusFilter != null && map['status'] != _statusFilter) return false;
              final q = _searchController.text.trim().toLowerCase();
              if (q.isNotEmpty && !(map['member_name'] as String? ?? '').toLowerCase().contains(q)) return false;
              return true;
            }).map((p) {
              final map = p as Map<String, dynamic>;
              return Card(
                color: AppTheme.surfaceVariant,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.primary.withOpacity(0.3))),
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: LayoutConstants.screenPadding(context), vertical: 8),
                  title: Text(map['member_name'] ?? '', style: GoogleFonts.poppins(color: AppTheme.onSurface, fontWeight: FontWeight.w500)),
                  subtitle: Text('${map['fee_type']} • ${map['period'] ?? 'Registration'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹${map['amount']}', style: GoogleFonts.poppins(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                      Text(map['status'] ?? '', style: TextStyle(color: _statusColor(map['status']), fontSize: 12)),
                    ],
                  ),
                ),
              );
            })),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String? s) {
    if (s == 'Paid') return AppTheme.success;
    if (s == 'Overdue') return Colors.orange;
    return AppTheme.primary;
  }

  // Kept for future use when editing payment status from the payments list.
  // ignore: unused_element
  static void _showEditPaymentStatus(BuildContext context, Map<String, dynamic> payment, VoidCallback onSuccess) {
    String selected = payment['status'] as String? ?? 'Due';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Edit payment status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${payment['member_name']} • ₹${payment['amount']} • ${payment['fee_type']}'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selected,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Due', child: Text('Due')),
                  DropdownMenuItem(value: 'Overdue', child: Text('Overdue')),
                  DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                ],
                onChanged: (v) => setState(() => selected = v ?? selected),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final pid = payment['id'] as String?;
                if (pid == null) return;
                try {
                  final r = await ApiClient.instance.patch(
                    '/payments/$pid',
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({'status': selected}),
                  );
                  if (ctx.mounted) {
                    if (r.statusCode >= 200 && r.statusCode < 300) {
                      ApiClient.instance.invalidateCache();
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Payment status updated')));
                      onSuccess();
                    } else {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: ${r.body}')));
                    }
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
}

class _FeeChip extends StatelessWidget {
  final String label;
  final String? subtitle;
  final int count;
  final int amount;
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;

  const _FeeChip(this.label, this.count, this.amount, this.color, {this.subtitle, this.isSelected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: isSelected ? color.withOpacity(0.12) : AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: isSelected ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixed-height header so all chips are same height (title + optional subtitle)
            SizedBox(
              height: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: GoogleFonts.poppins(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text('$count', style: GoogleFonts.poppins(color: AppTheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold)),
            Text('₹$amount', style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      ),
    );
  }
}
