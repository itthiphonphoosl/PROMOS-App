import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_service.dart';
import '../services/auth_storage.dart';
import 'home_page.dart';
import '../widgets/cooler_alert.dart';

const List<Map<String, String>> _kStations = [
  {'id': 'STA001', 'name': 'Casting'},
  {'id': 'STA002', 'name': 'Heat treatment'},
  {'id': 'STA003', 'name': 'Machine'},
  {'id': 'STA004', 'name': 'Checker'},
  {'id': 'STA005', 'name': 'Plating'},
  {'id': 'STA006', 'name': 'Painting'},
  {'id': 'STA007', 'name': 'Checker Assy'},
];

Map<String, dynamic> _safeJson(String body) {
  try {
    final d = jsonDecode(body);
    if (d is Map<String, dynamic>) return d;
  } catch (_) {}
  return {};
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameCtrl = TextEditingController();
  String? _selectedStaId;
  bool _loading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final username = _usernameCtrl.text.trim();

    if (username.isEmpty) {
      CoolerAlert.show(
        context,
        title: 'แจ้งเตือน',
        message: 'กรุณากรอก Username',
        type: CoolerAlertType.warning,
      );
      return;
    }
    if (_selectedStaId == null) {
      CoolerAlert.show(
        context,
        title: 'แจ้งเตือน',
        message: 'กรุณาเลือก Station',
        type: CoolerAlertType.warning,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // ส่งแค่ username + op_sta_id ไม่มี password (HH mode)
      final res = await ApiService.login(username, '', opStaId: _selectedStaId);
      final body = _safeJson(res.body);

      if (res.statusCode != 200) {
        CoolerAlert.show(
          context,
          title: 'เข้าสู่ระบบไม่สำเร็จ',
          message: body['message']?.toString() ?? 'เกิดข้อผิดพลาด',
          type: CoolerAlertType.error,
        );
        return;
      }

      final tokenAccess = body['tokenAccess']?.toString();
      final tokenExpires = body['tokenExpiresAt']?.toString();
      final userInfo = body['userInfo'];
      final ct = body['clientType']?.toString() ?? 'HH';

      if (tokenAccess == null ||
          tokenExpires == null ||
          userInfo is! Map<String, dynamic>) {
        CoolerAlert.show(
          context,
          title: 'แจ้งเตือน',
          message: 'รูปแบบข้อมูลตอบกลับไม่ถูกต้อง',
          type: CoolerAlertType.error,
        );
        return;
      }

      await AuthStorage.saveLogin(
        tokenAccess: tokenAccess,
        tokenExpiresAt: tokenExpires,
        clientType: ct,
        userInfo: userInfo,
      );

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    } catch (_) {
      CoolerAlert.show(
        context,
        title: 'แจ้งเตือน',
        message: 'เชื่อมต่อ Server ไม่ได้ กรุณาตรวจสอบเครือข่าย',
        type: CoolerAlertType.error,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selStation = _selectedStaId != null
        ? _kStations.firstWhere((s) => s['id'] == _selectedStaId)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Logo ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.factory_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'ProMoSystem',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                const Text(
                  'ระบบติดตามการผลิต',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 32),

                // ── Card ───────────────────────────────────
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'เข้าสู่ระบบ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'สำหรับพนักงาน (Operator)',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),

                        // ── Username ──────────────────────
                        TextField(
                          controller: _usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                          autofocus: true,
                        ),
                        const SizedBox(height: 16),

                        // ── Station Dropdown ───────────────
                        DropdownButtonFormField<String>(
                          value: _selectedStaId,
                          decoration: const InputDecoration(
                            labelText: 'Station',
                            prefixIcon: Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('เลือก Station'),
                          isExpanded: true,
                          menuMaxHeight: 320,
                          items: _kStations.map((s) {
                            return DropdownMenuItem<String>(
                              value: s['id'],
                              child: Row(
                                children: [
                                  // Badge STA00X
                                  Container(
                                    width: 60,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.indigo.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      s['id']!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      s['name']!,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => _selectedStaId = v),
                        ),

                        // แสดง station ที่เลือก
                        if (selStation != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.indigo,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${selStation['id']}  •  ${selStation['name']}',
                                  style: const TextStyle(
                                    color: Colors.indigo,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // ── ปุ่มเข้าสู่ระบบ ────────────────
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _loading ? null : _onSubmit,
                            child: _loading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'เข้าสู่ระบบ',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
