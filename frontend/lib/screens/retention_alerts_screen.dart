// ---------------------------------------------------------------------------
// Retention Alerts – at-risk members (7+ days since last visit).
// ---------------------------------------------------------------------------
// Lists active members with declining attendance. Tap card to open member
// detail; use Message to send a re-engagement message to that member.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'member_detail_screen.dart';

class RetentionAlertsScreen extends StatefulWidget {
  const RetentionAlertsScreen({super.key});

  @override
  State<RetentionAlertsScreen> createState() => _RetentionAlertsScreenState();
}

class _RetentionAlertsScreenState extends State<RetentionAlertsScreen> {
  List<RetentionAlert> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiClient.instance.getRetentionAlerts();
      if (mounted) {
        setState(() {
          _alerts = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().split('\n').first;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openMemberDetail(RetentionAlert alert) async {
    try {
      final member = await ApiClient.instance.getMember(alert.memberId);
      if (!mounted) return;
      if (member != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MemberDetailScreen(member: member),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load member')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  void _showSendMessageSheet(RetentionAlert alert) {
    final titleController = TextEditingController(text: 'We miss you at the gym!');
    final bodyController = TextEditingController();

    final isWeb = MediaQuery.sizeOf(context).width >= 600;
    if (isWeb) {
      showDialog(
        context: context,
        builder: (ctx) => _SendMessageDialog(
          alert: alert,
          titleController: titleController,
          bodyController: bodyController,
          onSent: () {
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent')));
          },
          onError: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _SendMessageForm(
              alert: alert,
              titleController: titleController,
              bodyController: bodyController,
              onSent: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent')));
              },
              onError: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
            ),
          ),
        ),
      );
    }
  }

  Color _riskColor(String riskLevel) {
    switch (riskLevel) {
      case 'Slipping':
        return Colors.amber.shade700;
      case 'High Risk':
        return Colors.orange.shade700;
      case 'Critical':
        return AppTheme.error;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retention Alerts'),
        leading: Tooltip(
          message: 'Back to dashboard',
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        actions: [
          Tooltip(
            message: 'Refresh',
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
          ),
          Tooltip(
            message: 'Logout',
            child: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => LoginScreen.logout(context),
            ),
          ),
        ],
      ),
      body: _loading && _alerts.isEmpty && _error == null
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey.shade700)),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.primary,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final padding = LayoutConstants.screenPadding(context);
                      final isWide = constraints.maxWidth >= 600;
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(padding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Retention Alerts',
                              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.onSurface),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Active members who haven’t visited in 7+ days. Slipping: 7–14 days · High Risk: 15–30 days · Critical: 30+ days. Tap a card to view member; use Message to send a re-engagement note.',
                              style: GoogleFonts.poppins(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            if (_alerts.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 48),
                                  child: Column(
                                    children: [
                                      Icon(Icons.celebration, size: 64, color: AppTheme.success),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No retention alerts',
                                        style: GoogleFonts.poppins(fontSize: 16, color: AppTheme.onSurface),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'All active members have visited in the last 7 days.',
                                        style: GoogleFonts.poppins(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (isWide)
                              Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: _alerts.map((a) => _buildCard(a)).toList(),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _alerts.length,
                                itemBuilder: (context, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildCard(_alerts[i]),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildCard(RetentionAlert alert) {
    final color = _riskColor(alert.riskLevel);
    final radius = LayoutConstants.cardRadius(context);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: color.withOpacity(0.5))),
      child: InkWell(
        onTap: () => _openMemberDetail(alert),
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.name,
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.phone,
                      style: GoogleFonts.poppins(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${alert.daysSinceLastVisit} days since last visit${alert.lastAttendanceDate != null ? " · ${alert.lastAttendanceDate}" : ""}',
                      style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color),
                      ),
                      child: Text(
                        alert.riskLevel,
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Send message to this member',
                child: IconButton(
                  icon: const Icon(Icons.message_outlined),
                  onPressed: () => _showSendMessageSheet(alert),
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog (web) wrapper for send message form.
class _SendMessageDialog extends StatefulWidget {
  final RetentionAlert alert;
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final VoidCallback onSent;
  final void Function(String) onError;

  const _SendMessageDialog({
    required this.alert,
    required this.titleController,
    required this.bodyController,
    required this.onSent,
    required this.onError,
  });

  @override
  State<_SendMessageDialog> createState() => _SendMessageDialogState();
}

class _SendMessageDialogState extends State<_SendMessageDialog> {
  bool _sending = false;

  Future<void> _send() async {
    final title = widget.titleController.text.trim();
    final body = widget.bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      widget.onError('Enter title and message');
      return;
    }
    setState(() => _sending = true);
    try {
      final ok = await ApiClient.instance.sendMessage(
        title: title,
        body: body,
        recipientType: 'members',
        recipientMemberIds: [widget.alert.memberId],
      );
      if (!mounted) return;
      if (ok) {
        widget.onSent();
      } else {
        widget.onError('Failed to send message');
      }
    } catch (e) {
      if (mounted) widget.onError('Error: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Send message to ${widget.alert.name}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: widget.titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.bodyController,
                decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
                maxLines: 4,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send'),
        ),
      ],
    );
  }
}

/// Form for send message (used in bottom sheet).
class _SendMessageForm extends StatefulWidget {
  final RetentionAlert alert;
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final VoidCallback onSent;
  final void Function(String) onError;

  const _SendMessageForm({
    required this.alert,
    required this.titleController,
    required this.bodyController,
    required this.onSent,
    required this.onError,
  });

  @override
  State<_SendMessageForm> createState() => _SendMessageFormState();
}

class _SendMessageFormState extends State<_SendMessageForm> {
  bool _sending = false;

  Future<void> _send() async {
    final title = widget.titleController.text.trim();
    final body = widget.bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      widget.onError('Enter title and message');
      return;
    }
    setState(() => _sending = true);
    try {
      final ok = await ApiClient.instance.sendMessage(
        title: title,
        body: body,
        recipientType: 'members',
        recipientMemberIds: [widget.alert.memberId],
      );
      if (!mounted) return;
      if (ok) {
        widget.onSent();
      } else {
        widget.onError('Failed to send message');
      }
    } catch (e) {
      if (mounted) widget.onError('Error: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Send message to ${widget.alert.name}', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        const SizedBox(height: 16),
        TextField(
          controller: widget.titleController,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.bodyController,
          decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
          maxLines: 4,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send'),
        ),
      ],
    );
  }
}
