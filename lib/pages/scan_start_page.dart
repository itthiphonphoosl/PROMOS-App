import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/material.dart';
import '../config/api_service.dart';
import '../widgets/cooler_alert.dart';
import 'scan_finish_page.dart';

class ScanStartPage extends StatefulWidget {
  const ScanStartPage({super.key});

  @override
  State<ScanStartPage> createState() => _ScanStartPageState();
}

class _ScanStartPageState extends State<ScanStartPage> {
  final _tkCtrl = TextEditingController();

  List<Map<String, dynamic>> _machines = [];
  String? _selectedMcId;
  String? _selectedMcName;
  Map<String, dynamic>? _tkDoc;

  bool _loadingMachines = true;
  bool _loadingTk = false;
  bool _starting = false;

  String? _stationName;

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  @override
  void dispose() {
    _tkCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMachines() async {
    setState(() => _loadingMachines = true);
    try {
      final res = await ApiService.getMachinesInStation();
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200) {
        final list =
            (body['machines'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        setState(() {
          _machines = list;
          _stationName = body['station']?['op_sta_name']?.toString();
          _loadingMachines = false;
        });
      } else {
        CoolerAlert.show(
          context,
          message: body['message']?.toString() ?? 'โหลด Machine ไม่ได้',
          type: CoolerAlertType.error,
        );
        setState(() => _loadingMachines = false);
      }
    } catch (_) {
      CoolerAlert.show(
        context,
        message: 'เชื่อมต่อ Server ไม่ได้',
        type: CoolerAlertType.error,
      );
      setState(() => _loadingMachines = false);
    }
  }

  Future<void> _lookupTk() async {
    final tkId = _tkCtrl.text.trim();
    if (tkId.isEmpty) return;
    setState(() {
      _loadingTk = true;
      _tkDoc = null;
    });

    try {
      final res = await ApiService.getTkDocById(tkId);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200) {
        setState(() => _tkDoc = body);
      } else if (res.statusCode == 404) {
        CoolerAlert.show(
          context,
          message: body['message']?.toString() ?? 'ไม่พบ Tracking No. นี้',
          type: CoolerAlertType.warning,
        );
      } else if (res.statusCode == 403) {
        CoolerAlert.show(
          context,
          title: 'เอกสารถูกปิดการใช้งาน',
          message:
              body['message']?.toString() ??
              'เอกสารนี้ถูกปิดการใช้งาน กรุณาติดต่อ Admin',
          type: CoolerAlertType.error,
        );
      } else {
        CoolerAlert.show(
          context,
          message: body['message']?.toString() ?? 'เกิดข้อผิดพลาด กรุณาลองใหม่',
          type: CoolerAlertType.error,
        );
      }
    } catch (_) {
      CoolerAlert.show(
        context,
        message: 'เชื่อมต่อ Server ไม่ได้',
        type: CoolerAlertType.error,
      );
    } finally {
      if (mounted) setState(() => _loadingTk = false);
    }
  }

  Future<void> _openQrScanner() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
    if (result != null && result.isNotEmpty) {
      _tkCtrl.text = result;
      _lookupTk();
    }
  }

  Future<void> _start() async {
    final tkId = _tkCtrl.text.trim();
    if (tkId.isEmpty) {
      CoolerAlert.show(
        context,
        message: 'กรุณากรอก Tracking No.',
        type: CoolerAlertType.warning,
      );
      return;
    }
    if (_selectedMcId == null) {
      CoolerAlert.show(
        context,
        message: 'กรุณาเลือก Machine',
        type: CoolerAlertType.warning,
      );
      return;
    }

    setState(() => _starting = true);
    try {
      final res = await ApiService.startScan(tkId: tkId, mcId: _selectedMcId!);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 201) {
        CoolerAlert.show(
          context,
          title: 'เริ่มงานสำเร็จ',
          message: 'op_sc_id: ${body['op_sc_id']}',
          type: CoolerAlertType.success,
        );

        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ScanFinishPage(
              opScId: body['op_sc_id']?.toString() ?? '',
              tkId: tkId,
              tkDoc: body['tk_doc'] as Map<String, dynamic>? ?? {},
              allLots:
                  (body['current_lots'] as List?)
                      ?.map((e) => Map<String, dynamic>.from(e as Map))
                      .toList() ??
                  [],
            ),
          ),
        );
      } else {
        final msg = body['message']?.toString() ?? 'Start ไม่สำเร็จ';
        // [FIX] key เปลี่ยนจาก next_sta → suggested_next_sta
        final nextSta = body['suggested_next_sta']?.toString();
        final nextStaName = body['suggested_next_sta_name']?.toString();

        final display = (nextSta != null)
            ? '$msg\n\n➡ ถัดไป: $nextSta ($nextStaName)'
            : msg;

        CoolerAlert.show(
          context,
          title: 'ไม่สามารถเริ่มงานได้',
          message: display,
          type: CoolerAlertType.error,
          duration: const Duration(seconds: 5),
        );
      }
    } catch (_) {
      CoolerAlert.show(
        context,
        message: 'เชื่อมต่อ Server ไม่ได้',
        type: CoolerAlertType.error,
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Start Scan'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMachines),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Station badge
            if (_stationName != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Station: $_stationName',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // TK ID Input
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'สแกน / กรอก Tracking No.',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tkCtrl,
                            decoration: InputDecoration(
                              hintText: 'กรุณากรอก Tracking No.',
                              prefixIcon: GestureDetector(
                                onTap: _openQrScanner,
                                child: const Tooltip(
                                  message: 'สแกน QR Code',
                                  child: Icon(
                                    Icons.qr_code,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _lookupTk(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _loadingTk ? null : _lookupTk,
                          icon: _loadingTk
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.search),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.indigo,
                          ),
                        ),
                      ],
                    ),

                    // TK Info
                    if (_tkDoc != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Row(
                              'Part No',
                              _tkDoc!['detail']?['part_no']?.toString() ?? '-',
                            ),
                            _Row(
                              'Part Name',
                              _tkDoc!['detail']?['part_name']?.toString() ??
                                  '-',
                            ),
                            _Row(
                              'Lot No',
                              _tkDoc!['lot_no']?.toString() ?? '-',
                            ),
                            _Row('Status', _statusLabel(_tkDoc!['tk_status'])),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Machine Select
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'เลือก Machine',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _loadingMachines
                        ? const Center(child: CircularProgressIndicator())
                        : _machines.isEmpty
                        ? const Text(
                            'ไม่พบ Machine ใน Station นี้',
                            style: TextStyle(color: Colors.grey),
                          )
                        : Column(
                            children: _machines.map((m) {
                              final id = m['mc_id']?.toString() ?? '';
                              final name = m['mc_name']?.toString() ?? '';
                              final sel = _selectedMcId == id;
                              return GestureDetector(
                                onTap: () => setState(() {
                                  _selectedMcId = id;
                                  _selectedMcName = name;
                                }),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? Colors.green.shade50
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: sel
                                          ? Colors.green
                                          : Colors.grey.shade300,
                                      width: sel ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        sel
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        color: sel ? Colors.green : Colors.grey,
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            id,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Start Button
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _starting ? null : _start,
                icon: _starting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_circle_outline),
                label: Text(
                  _starting ? 'กำลังเริ่ม...' : 'เริ่มงาน (Start)',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(dynamic s) {
    switch (s) {
      case 0:
        return '⬜ รอดำเนินการ';
      case 1:
        return '✅ เสร็จสิ้น (ครบ Line)';
      case 2:
        return '🔄 ผ่านบางสถานี';
      case 3:
        return '🟡 กำลังดำเนินการ';
      default:
        return '-';
    }
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
// QR Scanner Page (mobile_scanner)
// ══════════════════════════════════════════════════════════════════
class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _hasResult = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasResult) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    _hasResult = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan TK QR'),
        actions: [
          IconButton(
            tooltip: 'สลับกล้อง',
            icon: const Icon(Icons.flip_camera_ios_rounded),
            onPressed: _ctrl.switchCamera,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          // Overlay frame
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Hint text
          Align(
            alignment: const Alignment(0, 0.75),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Align the QR code inside the box',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          // ( สแกน QR Code )
          Align(
            alignment: const Alignment(0, 0.92),
            child: const Text(
              '( สแกน QR Code )',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
