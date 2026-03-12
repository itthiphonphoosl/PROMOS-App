import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/api_service.dart';
import '../widgets/cooler_alert.dart';
import 'summary_page.dart';

class SummarySearchPage extends StatefulWidget {
  const SummarySearchPage({super.key});

  @override
  State<SummarySearchPage> createState() => _SummarySearchPageState();
}

class _SummarySearchPageState extends State<SummarySearchPage> {
  final _tkCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _tkCtrl.dispose();
    super.dispose();
  }

  /// ตรวจสอบจาก API ก่อน ถ้าไม่พบ → alert อยู่หน้าเดิม ไม่เด้งไปไหน
  Future<void> _open() async {
    final tkId = _tkCtrl.text.trim();
    if (tkId.isEmpty) return;

    setState(() => _loading = true);
    try {
      final res = await ApiService.getSummaryByTkId(tkId);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (!mounted) return;

      if (res.statusCode == 200) {
        // พบข้อมูล → เด้งไปหน้า Summary พร้อม pre-loaded data
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SummaryPage(tkId: tkId, finishResult: body),
          ),
        );
      } else {
        // error → แสดง alert อยู่หน้าเดิม ไม่เด้งไปไหนเลย
        final rawMsg = body['message']?.toString() ?? 'เกิดข้อผิดพลาด';
        final displayMsg = rawMsg
            .replaceAll('tk_id', 'Tracking No.')
            .replaceAll('not found', 'ไม่มีอยู่ในระบบ')
            .replaceAll('Not found', 'ไม่มีอยู่ในระบบ');
        CoolerAlert.show(
          context,
          title: res.statusCode == 404
              ? 'ไม่พบ Tracking No.'
              : 'เกิดข้อผิดพลาด',
          message: res.statusCode == 404
              ? 'Tracking No. นี้ไม่มีอยู่ในระบบ'
              : displayMsg,
          type: res.statusCode == 404
              ? CoolerAlertType.warning
              : CoolerAlertType.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      CoolerAlert.show(
        context,
        message: 'เชื่อมต่อ Server ไม่ได้',
        type: CoolerAlertType.error,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openQrScanner() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
    if (result != null && result.isNotEmpty) {
      _tkCtrl.text = result;
      _open();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Summary'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading
                ? null
                : () {
                    _tkCtrl.clear();
                  },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Search field + QR button (เหมือน Start Scan) ──
            Card(
              elevation: 2,
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
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _tkCtrl,
                      decoration: InputDecoration(
                        hintText: 'กรุณากรอก Tracking No.',
                        prefixIcon: GestureDetector(
                          onTap: _openQrScanner,
                          child: const Icon(
                            Icons.qr_code_scanner,
                            color: Colors.blue,
                          ),
                        ),
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.blue.shade400,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 12,
                        ),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _open(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── ปุ่ม Open Summary ──
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _loading ? null : _open,
                icon: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  _loading ? 'กำลังค้นหา...' : 'Open Summary',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// QR Scanner Page (เหมือน scan_start_page.dart ทุกอย่าง)
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
          const Align(
            alignment: Alignment(0, 0.92),
            child: Text(
              '( สแกน QR Code )',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
