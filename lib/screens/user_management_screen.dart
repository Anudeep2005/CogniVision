import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchUsers(silent: true);
    });
  }

  Future<void> _fetchUsers({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final users = await _authService.getAllUsers();
    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _generateTokenForUser(String userId) async {
    final data = await _authService.generateRecoveryData(userId);
    if (data.containsKey('token')) {
      _showTokenDialog(data['token']);
      _fetchUsers(); // Refresh list
    }
  }

  void _showTokenDialog(String token) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Generated Recovery Token', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This token can be used by the guardian to unlock the account.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                token,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: token));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Token copied to clipboard')),
              );
            },
            child: const Text('COPY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                final isUser = user['role'] == 'user';
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: isUser ? const Color(0xFF6366F1).withOpacity(0.2) : Colors.white10,
                      child: Icon(
                        isUser ? Icons.person : Icons.admin_panel_settings,
                        color: isUser ? const Color(0xFF6366F1) : Colors.white54,
                      ),
                    ),
                    title: Text(
                      user['email'],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: user['isLocked'] ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            user['isLocked'] ? 'LOCKED' : 'ACTIVE',
                            style: TextStyle(
                              color: user['isLocked'] ? Colors.redAccent : Colors.greenAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (user['hasToken']) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.key, color: Colors.orangeAccent, size: 14),
                          const Text(' Token Active', style: TextStyle(color: Colors.orangeAccent, fontSize: 10)),
                        ],
                      ],
                    ),
                    trailing: isUser && user['isLocked']
                        ? ElevatedButton(
                            onPressed: () => _generateTokenForUser(user['id']),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: const Size(0, 36),
                            ),
                            child: const Text('GET TOKEN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }
}
