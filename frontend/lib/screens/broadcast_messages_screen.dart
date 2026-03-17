// ---------------------------------------------------------------------------
// Broadcast Messages – gym admin: compose broadcast or one-to-one messages,
// list sent messages with edit/delete. Messages appear in member inbox.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/date_utils.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class BroadcastMessagesScreen extends StatefulWidget {
  const BroadcastMessagesScreen({super.key});

  @override
  State<BroadcastMessagesScreen> createState() => _BroadcastMessagesScreenState();
}

class _BroadcastMessagesScreenState extends State<BroadcastMessagesScreen> {
  List<Map<String, dynamic>> _sentMessages = [];
  List<Member> _members = [];
  bool _loadingSent = true;
  bool _loadingMembers = false;
  bool _sending = false;
  String _recipientType = 'all_active';
  final List<String> _selectedMemberIds = [];
  /// Members with Due/Overdue payments (from GET /payments/members-with-due).
  List<Map<String, dynamic>> _membersWithDue = [];
  bool _loadingMembersWithDue = false;
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSent();
    _loadMembers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadSent() async {
    setState(() => _loadingSent = true);
    try {
      final r = await ApiClient.instance.get(
        '/messages',
        // Only load active (non-deleted) messages so deleted ones disappear from the list.
        useCache: false,
      );
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        final list = jsonDecode(r.body) as List<dynamic>? ?? [];
        setState(() {
          _sentMessages = list
              .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
              .where((m) => m['deleted_at'] == null)
              .toList();
          _loadingSent = false;
        });
      } else {
        if (mounted) {
          setState(() => _loadingSent = false);
          if (r.statusCode == 404) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Messages API not found (404). Ensure your server is up to date and supports GET /messages.'),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSent = false);
    }
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    try {
      final r = await ApiClient.instance.get('/members', queryParameters: {'brief': 'true', 'limit': '500'}, useCache: false);
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        setState(() {
          _members = ApiClient.parseMembers(r.body);
          _loadingMembers = false;
        });
      } else if (mounted) setState(() => _loadingMembers = false);
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _loadMembersWithDue() async {
    setState(() => _loadingMembersWithDue = true);
    try {
      final r = await ApiClient.instance.get('/payments/members-with-due', useCache: false);
      if (mounted && r.statusCode >= 200 && r.statusCode < 300) {
        final list = jsonDecode(r.body) as List<dynamic>? ?? [];
        setState(() {
          _membersWithDue = list.map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>)).toList();
          _loadingMembersWithDue = false;
        });
      } else if (mounted) setState(() => _loadingMembersWithDue = false);
    } catch (_) {
      if (mounted) setState(() => _loadingMembersWithDue = false);
    }
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a title')));
      return;
    }
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter message body')));
      return;
    }
    if (_recipientType == 'members' && _selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one member')));
      return;
    }
    if (_recipientType == 'members_with_due') {
      if (_membersWithDue.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No members with due payments. Add recipients or choose another option.')));
        return;
      }
    }
    setState(() => _sending = true);
    try {
      String effectiveType = _recipientType;
      List<String> effectiveIds = _selectedMemberIds;
      if (_recipientType == 'members_with_due') {
        effectiveType = 'members';
        effectiveIds = _membersWithDue.map((e) => e['member_id'] as String).toList();
      }
      final payload = <String, dynamic>{
        'title': title,
        'body': body,
        'recipient_type': effectiveType,
      };
      if (effectiveType == 'members') payload['recipient_member_ids'] = effectiveIds;
      final r = await ApiClient.instance.post(
        '/messages',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _titleController.clear();
        _bodyController.clear();
        setState(() {
          _selectedMemberIds.clear();
          if (_recipientType == 'members_with_due') _membersWithDue = [];
        });
        await _loadSent();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent')));
      } else {
        String err = 'Failed to send';
        try {
          final body = jsonDecode(r.body) as Map<String, dynamic>?;
          err = body?['detail']?.toString() ?? err;
        } catch (_) {
          if (r.body.isNotEmpty) err = r.body;
        }
        final is404 = r.statusCode == 404;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(is404
                ? 'Messages API not found (404). Ensure your server is up to date and supports POST /messages.'
                : err),
            duration: is404 ? const Duration(seconds: 5) : const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().split('\n').first}')));
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _editMessage(Map<String, dynamic> msg) async {
    final id = msg['id'] as String?;
    if (id == null) return;
    final titleController = TextEditingController(text: msg['title']?.toString() ?? '');
    final bodyController = TextEditingController(text: msg['body']?.toString() ?? '');
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit message', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: bodyController,
                decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
                style: GoogleFonts.poppins(),
                maxLines: 5,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated != true || !mounted) return;
    try {
      final r = await ApiClient.instance.patch(
        '/messages/$id',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': titleController.text.trim(), 'body': bodyController.text.trim()}),
      );
      if (mounted) {
        if (r.statusCode >= 200 && r.statusCode < 300) {
          await _loadSent();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message updated')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((jsonDecode(r.body) as Map?)?['detail']?.toString() ?? 'Update failed')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    final id = msg['id'] as String?;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This will remove the message from member inboxes. You cannot undo this.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final r = await ApiClient.instance.delete('/messages/$id');
      if (mounted) {
        if (r.statusCode >= 200 && r.statusCode < 300) {
          await _loadSent();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message deleted')));
        }
      }
    } catch (_) {}
  }

  static String _formatDate(dynamic v) {
    if (v == null) return '—';
    try {
      final dt = parseApiDateTime(v.toString());
      return dt != null ? formatDisplayDateTime(dt) : v.toString();
    } catch (_) {
      return v.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = LayoutConstants.screenPadding(context);
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: 'Back to dashboard',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text('Broadcast Messages', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => LoginScreen.logout(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Compose
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
                          Icon(FontAwesomeIcons.paperPlane, size: 20, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Text('Compose', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('To', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _recipientType,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all_active', child: Text('All active members')),
                          DropdownMenuItem(value: 'members_with_due', child: Text('Members with due payments')),
                          DropdownMenuItem(value: 'members', child: Text('Select members manually')),
                        ],
                        onChanged: (v) {
                          setState(() => _recipientType = v ?? 'all_active');
                          if (v == 'members_with_due') _loadMembersWithDue();
                        },
                      ),
                      if (_recipientType == 'members_with_due') ...[
                        const SizedBox(height: 12),
                        _loadingMembersWithDue
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                              )
                            : _membersWithDue.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'No members with due or overdue payments.',
                                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.people_outline, size: 20, color: AppTheme.primary),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                '${_membersWithDue.length} member${_membersWithDue.length == 1 ? '' : 's'} with due payments will receive this message.',
                                                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.onSurface),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextButton.icon(
                                        onPressed: _loadingMembersWithDue ? null : _loadMembersWithDue,
                                        icon: Icon(Icons.refresh, size: 18, color: AppTheme.primary),
                                        label: Text('Refresh list', style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.primary)),
                                      ),
                                      const SizedBox(height: 4),
                                      ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        title: Text('View list', style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.primary)),
                                        children: [
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxHeight: 180),
                                            child: ListView.builder(
                                              shrinkWrap: true,
                                              itemCount: _membersWithDue.length,
                                              itemBuilder: (ctx, i) {
                                                final e = _membersWithDue[i];
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                                  child: Text(
                                                    '• ${e['member_name'] ?? e['member_id'] ?? '—'}',
                                                    style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.onSurface),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                      ],
                      if (_recipientType == 'members') ...[
                        const SizedBox(height: 12),
                        Text('Select members', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: _loadingMembers
                              ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppTheme.primary)))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _members.length,
                                  itemBuilder: (ctx, i) {
                                    final m = _members[i];
                                    final selected = _selectedMemberIds.contains(m.id);
                                    return CheckboxListTile(
                                      value: selected,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selectedMemberIds.add(m.id);
                                          } else {
                                            _selectedMemberIds.remove(m.id);
                                          }
                                        });
                                      },
                                      title: Text('${m.name} (${m.phone})', style: GoogleFonts.poppins(fontSize: 14)),
                                      controlAffinity: ListTileControlAffinity.leading,
                                    );
                                  },
                                ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Gym holiday tomorrow'),
                        style: GoogleFonts.poppins(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _bodyController,
                        decoration: const InputDecoration(labelText: 'Message', hintText: 'Write your message...', alignLabelWithHint: true),
                        style: GoogleFonts.poppins(),
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: (_sending ||
                                  (_recipientType == 'members_with_due' && _membersWithDue.isEmpty))
                              ? null
                              : _send,
                          icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary)) : const Icon(Icons.send_rounded, size: 20),
                          label: Text(_sending ? 'Sending...' : 'Send message'),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Sent
              Row(
                children: [
                  Icon(FontAwesomeIcons.inbox, size: 20, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text('Sent messages', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                ],
              ),
              const SizedBox(height: 12),
              if (_loadingSent)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppTheme.primary)))
              else if (_sentMessages.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No messages sent yet.', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
                )
              else
                ..._sentMessages.map((msg) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: AppTheme.surfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: EdgeInsets.all(padding),
                      title: Text(
                        msg['title']?.toString() ?? '—',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            (msg['body']?.toString() ?? '').length > 80 ? '${(msg['body'] as String).substring(0, 80)}...' : (msg['body']?.toString() ?? ''),
                            style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Chip(
                                label: Text(
                                  msg['recipient_type'] == 'all_active' ? 'All active' : '${(msg['recipient_member_ids'] as List?)?.length ?? 0} members',
                                  style: GoogleFonts.poppins(fontSize: 11),
                                ),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              const SizedBox(width: 8),
                              Text(_formatDate(msg['created_at']), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _editMessage(msg);
                                if (v == 'delete') _deleteMessage(msg);
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppTheme.error))),
                              ],
                            ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
