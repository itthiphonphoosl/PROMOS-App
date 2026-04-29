import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_service.dart';
import '../services/auth_storage.dart';
import 'home_page.dart';
import '../widgets/cooler_alert.dart';

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

  // ── Stations จาก API ─────────────────────────────────────
  List<Map<String, String>> _stations = [];
  bool _loadingStations = true;
  String? _stationsError;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    setState(() {
      _loadingStations = true;
      _stationsError = null;
    });
    try {
      final res = await ApiService.getPublicStations();
      if (res.statusCode == 200) {
        final body = _safeJson(res.body);
        final list = body['stations'];
        if (list is List) {
          setState(() {
            _stations = list
                .map(
                  (e) => {
                    'id': e['op_sta_id']?.toString() ?? '',
                    'name': e['op_sta_name']?.toString() ?? '',
                  },
                )
                .toList();
            _loadingStations = false;
          });
          return;
        }
      }
      setState(() {
        _stationsError = 'ดึงข้อมูล Station ไม่ได้';
        _loadingStations = false;
      });
    } catch (_) {
      setState(() {
        _stationsError = 'เชื่อมต่อ Server ไม่ได้';
        _loadingStations = false;
      });
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<bool> _showStationConfirm({
    required String firstname,
    required String lastname,
    required String staId,
    required String staName,
  }) async {
    const _orange = Color(0xFFF39C12);
    const _orangeDark = Color(0xFFE67E22);
    const _orangeBg = Color(0xFFFFF8E7);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            decoration: BoxDecoration(
              color: _orangeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _orangeDark.withOpacity(0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _orange.withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── แถบส้มบน ──
                Container(
                  height: 6,
                  decoration: const BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── ไอคอน ──
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _orange,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: _orange.withOpacity(0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.warning_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // ── ข้อความ ──
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ยืนยันการเข้าสู่ระบบ',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: _orange,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF2D3436),
                                      height: 1.6,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    children: [
                                      const TextSpan(text: 'คุณ '),
                                      TextSpan(
                                        text: '$firstname $lastname',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: ' ต้องการเข้าทำงานที่ ',
                                      ),
                                      TextSpan(
                                        text: '$staId : $staName',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                      const TextSpan(text: ' นี้ใช่หรือไม่?'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                side: const BorderSide(color: Colors.grey),
                              ),
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text(
                                'ยกเลิก',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'ยืนยัน',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return result == true;
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

      // ── confirm ก่อน navigate ──────────────────────────────
      final firstname = userInfo['u_firstname']?.toString() ?? '';
      final lastname = userInfo['u_lastname']?.toString() ?? '';
      final staId = userInfo['op_sta_id']?.toString() ?? _selectedStaId ?? '';
      final staName = userInfo['op_sta_name']?.toString() ?? '';

      if (!mounted) return;
      final confirmed = await _showStationConfirm(
        firstname: firstname,
        lastname: lastname,
        staId: staId,
        staName: staName,
      );
      if (!confirmed) return; // กด ยกเลิก → อยู่หน้า login เฉยๆ

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
    final selStation = _selectedStaId != null && _stations.isNotEmpty
        ? _stations.firstWhere(
            (s) => s['id'] == _selectedStaId,
            orElse: () => <String, String>{},
          )
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
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
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: Offset.zero,
                      ),
                    ],
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
                        if (_loadingStations)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'กำลังโหลด Station...',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        else if (_stationsError != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.red,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _stationsError!,
                                        style: const TextStyle(
                                          color: Colors.red,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _loadStations,
                                      child: const Text('ลองใหม่'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
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
                            items: _stations.map((s) {
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
                            onChanged: (v) =>
                                setState(() => _selectedStaId = v),
                          ),

                        // แสดง station ที่เลือก
                        if (selStation != null && selStation.isNotEmpty) ...[
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
