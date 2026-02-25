// ---------------------------------------------------------------------------
// Super Admin – manage gym admins only: list, create, enable/disable.
// ---------------------------------------------------------------------------
// Super admin sees ONLY: list of admins (gym name, login id, active status).
// Actions: Create admin (gym name + login id + password), Enable/Disable.
// No gym details, no members, no payments – minimal list + actions only.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/secure_storage.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen> {
  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;
  String? _error;

  Future<String?> _getToken() async => SecureStorage.getAuthToken();

  Future<void> _loadAdmins() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _error = 'Not signed in');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ApiClient.instance.get(
        '/super-admin/admins',
        headers: {'Authorization': 'Bearer $token'},
        useCache: false,
      );
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final list = jsonDecode(r.body) as List<dynamic>? ?? [];
        setState(() {
          _admins = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Failed to load admins';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Could not load admins. Check connection.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  Future<void> _createAdmin() async {
    final gymName = TextEditingController();
    final loginId = TextEditingController();
    final password = TextEditingController();
    final obscure = ValueNotifier(true);
    final loading = ValueNotifier(false);

    await showDialog(
      context: context,
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: loading,
        builder: (_, loadingVal, __) => ValueListenableBuilder<bool>(
          valueListenable: obscure,
          builder: (_, obs, __) => AlertDialog(
            title: Text('Create gym admin', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Gym name', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: gymName,
                    decoration: const InputDecoration(hintText: 'e.g. Jupiter Arena'),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  Text('Admin login (email or phone)', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: loginId,
                    decoration: const InputDecoration(hintText: 'e.g. admin@gym.com'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  Text('Password', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: password,
                    obscureText: obs,
                    decoration: InputDecoration(
                      hintText: 'Min 6 characters',
                      suffixIcon: IconButton(
                        icon: Icon(obs ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => obscure.value = !obscure.value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: loadingVal ? null : () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: loadingVal
                    ? null
                    : () async {
                        final g = gymName.text.trim();
                        final l = loginId.text.trim();
                        final p = password.text;
                        if (g.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter gym name')));
                          return;
                        }
                        if (l.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter login ID')));
                          return;
                        }
                        if (p.length < 6) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters')));
                          return;
                        }
                        loading.value = true;
                        final token = await _getToken();
                        if (token == null) {
                          loading.value = false;
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Not signed in')));
                          return;
                        }
                        try {
                          final r = await ApiClient.instance.post(
                            '/super-admin/admins',
                            headers: {
                              'Content-Type': 'application/json',
                              'Authorization': 'Bearer $token',
                            },
                            body: jsonEncode({
                              'gym_name': g,
                              'admin_login_id': l,
                              'admin_password': p,
                            }),
                          );
                          if (r.statusCode >= 200 && r.statusCode < 300 && ctx.mounted) {
                            Navigator.of(ctx).pop();
                            _loadAdmins();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin created')));
                          } else {
                            loading.value = false;
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Failed to create admin')));
                          }
                        } catch (_) {
                          loading.value = false;
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Request failed')));
                        }
                      },
                child: loadingVal
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setActive(String adminId, bool isActive) async {
    final token = await _getToken();
    if (token == null) return;
    try {
      final r = await ApiClient.instance.patch(
        '/super-admin/admins/$adminId',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'is_active': isActive}),
      );
      if (r.statusCode >= 200 && r.statusCode < 300 && mounted) {
        _loadAdmins();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isActive ? 'Admin enabled' : 'Admin disabled')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action failed')));
      }
    }
  }

  Future<void> _logout() async {
    await SecureStorage.setAuthToken(null);
    await SecureStorage.setAuthRole(null);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surface = Theme.of(context).colorScheme.surface;
    final padding = LayoutConstants.screenPadding(context);
    final radius = LayoutConstants.cardRadius(context);

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: Text('Super Admin', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Log out',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAdmins,
              child: ListView(
                padding: EdgeInsets.all(padding),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: GoogleFonts.poppins(color: AppTheme.error)),
                    const SizedBox(height: 16),
                  ],
                  OutlinedButton.icon(
                    onPressed: _createAdmin,
                    icon: const Icon(Icons.add),
                    label: const Text('Create gym admin'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Gym admins (list only – create, enable, or disable)',
                    style: GoogleFonts.poppins(fontSize: 14, color: onSurface.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 12),
                  if (_admins.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No gym admins yet. Tap "Create gym admin" to add one.',
                        style: GoogleFonts.poppins(color: onSurface.withOpacity(0.6)),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._admins.map((a) {
                      final id = a['id'] as String? ?? '';
                      final gymName = a['gym_name'] as String? ?? '';
                      final loginId = a['login_id'] as String? ?? '';
                      final isActive = a['is_active'] as bool? ?? true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(gymName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Text(loginId, style: GoogleFonts.poppins(fontSize: 14, color: onSurface.withOpacity(0.8))),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isActive ? Colors.green.shade100 : Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isActive ? 'Active' : 'Disabled',
                                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (isActive)
                                    TextButton(
                                      onPressed: () => _setActive(id, false),
                                      child: const Text('Disable'),
                                    )
                                  else
                                    FilledButton(
                                      onPressed: () => _setActive(id, true),
                                      child: const Text('Enable'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
