import 'package:flutter/material.dart';
import '../services/auth_storage.dart';
import '../services/app_nav.dart';
import '../config/api_service.dart';
import '../widgets/cooler_alert.dart';
import 'scan_start_page.dart';
import 'active_scan_page.dart';
import 'summary_page.dart';
import 'summary_search_page.dart';
import 'parked_lots_page.dart'; // ✅ import หน้าใหม่

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final token = await AuthStorage.getToken();
    if (token == null) {
      await forceToLogin();
      return;
    }
    final expired = await AuthStorage.isTokenExpired();
    if (expired) {
      await forceToLogin();
      return;
    }
    final user = await AuthStorage.getUserInfo();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
    });
  }

  String get _name =>
      (('${_user?["u_firstname"] ?? ""} ${_user?["u_lastname"] ?? ""}'.trim())
          .isNotEmpty)
      ? '${_user?["u_firstname"] ?? ""} ${_user?["u_lastname"] ?? ""}'.trim()
      : '-';
  String get _role => _user?['role'] ?? '-';
  String get _uType => _user?['u_type'] ?? '-';
  String get _staId => _user?['op_sta_id'] ?? '';
  String get _staName => _user?['op_sta_name'] ?? '';
  bool get _isOp => _uType == 'op';

  String _roleLabel() {
    switch (_uType) {
      case 'op':
        return 'Operator';
      case 'ad':
        return 'Admin';
      case 'ma':
        return 'Manager';
      default:
        return _role;
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ออกจากระบบ'),
        content: const Text('ต้องการออกจากระบบใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ออกจากระบบ',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.logout();
    } catch (_) {}
    await forceToLogin();
  }

  void _goTo(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: const Text('ProMoSystem'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Column(
        children: [
          // ── User Info Banner ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo, Color(0xFF5C6BC0)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white24,
                      child: Text(
                        _name.isNotEmpty ? _name[0] : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _roleLabel(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_isOp && _staId.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_staId  •  $_staName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Menu Grid ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  // ── Operator menus ──
                  if (_isOp) ...[
                    _MenuCard(
                      icon: Icons.qr_code_scanner,
                      label: 'Start Scan',
                      subtitle: 'เริ่มสแกนถาด',
                      color: Colors.green,
                      onTap: () => _goTo(const ScanStartPage()),
                    ),
                    _MenuCard(
                      icon: Icons.assignment_turned_in_outlined,
                      label: 'Active Scans',
                      subtitle: 'งานที่กำลังทำอยู่',
                      color: Colors.orange,
                      onTap: () => _goTo(const ActiveScanPage()),
                    ),
                    // ✅ เมนูใหม่ — Lot ที่พักไว้
                    _MenuCard(
                      icon: Icons.inventory_2_outlined,
                      label: 'Lot ที่พักไว้',
                      subtitle: 'ดู Lot รอดำเนินการ',
                      color: Colors.blue,
                      onTap: () => _goTo(const ParkedLotsPage()),
                    ),
                  ],

                  // ── Common menus ──
                  _MenuCard(
                    icon: Icons.summarize_outlined,
                    label: 'Summary',
                    subtitle: 'ดูสรุปถาด',
                    color: Colors.teal,
                    onTap: () => _goTo(const SummarySearchPage()),
                  ),
                  _MenuCard(
                    icon: Icons.person_outline,
                    label: 'บัญชีของฉัน',
                    subtitle: 'ข้อมูลผู้ใช้',
                    color: Colors.purple,
                    onTap: () => _showUserInfo(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ข้อมูลผู้ใช้'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow('ชื่อ', _name),
            _InfoRow('ประเภท', _roleLabel()),
            if (_staId.isNotEmpty) _InfoRow('Station', '$_staId ($_staName)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              spreadRadius: 0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
