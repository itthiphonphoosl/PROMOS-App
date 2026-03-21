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
  // เปลี่ยนจาก tk_id → รับ lot_no แทน
  final _lotCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _lotCtrl.dispose();
    super.dispose();
  }

  /// step 1: lookup tk_id จาก lot_no
  /// step 2: ดึง summary ด้วย tk_id ที่ได้
  Future<void> _open() async {
    final lotNo = _lotCtrl.text.trim();
    if (lotNo.isEmpty) return;

    setState(() => _loading = true);
    try {
      // ── step 1: lot_no → tk_id ──────────────────────────────
      final lookupRes = await ApiService.lookupTkByLotNo(lotNo);
      final lookupBody = jsonDecode(lookupRes.body) as Map<String, dynamic>;

      if (!mounted) return;

      if (lookupRes.statusCode != 200) {
        // ── lookup ล้มเหลว ──
        if (lookupRes.statusCode == 404) {
          CoolerAlert.show(
            context,
            title: 'ไม่พบ Lot No.',
            message: 'Lot No. นี้ไม่มีอยู่ในระบบ',
            type: CoolerAlertType.warning,
          );
          return;
        } else if (lookupRes.statusCode == 403) {
          final msg = lookupBody['message']?.toString() ?? '';
          // ✅ เช็ค parked_at_sta / parked_lot_no ที่ backend ส่งมาจริง
          final isParked =
              lookupBody['parked'] == true ||
              lookupBody['parked_at_sta'] != null ||
              lookupBody['parked_lot_no'] != null ||
              msg.contains('ถูกพักไว้');

          // parked lot → แจ้งเตือนแล้วเด้งไปหน้า summary ต่อได้เลย
          if (isParked) {
            final parkedSta = lookupBody['parked_at_sta']?.toString() ?? '-';
            final tkIdParked = lookupBody['tk_id']?.toString() ?? '';
            // ตัด "ยังไม่สามารถเริ่มงานได้" ออก — หน้า summary ดูข้อมูลเท่านั้น ไม่ได้ start งาน
            final displayMsg = msg
                .replaceAll(' ยังไม่สามารถเริ่มงานได้', '')
                .replaceAll('ยังไม่สามารถเริ่มงานได้', '')
                .trim();
            CoolerAlert.show(
              context,
              title: 'Lot ถูกพักไว้ที่ $parkedSta',
              message: displayMsg,
              type: CoolerAlertType.warning,
              duration: const Duration(seconds: 3),
            );
            // ดึง summary ต่อด้วย tk_id ที่ได้มา
            if (tkIdParked.isNotEmpty) {
              final summaryRes = await ApiService.getSummaryByTkId(tkIdParked);
              final summaryBody =
                  jsonDecode(summaryRes.body) as Map<String, dynamic>;
              if (!mounted) return;
              if (summaryRes.statusCode == 200) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SummaryPage(
                      tkId: tkIdParked,
                      finishResult: summaryBody,
                    ),
                  ),
                );
              }
            }
            return;
          }

          // กรณีอื่น (cancel / closed) → แจ้งเตือนอย่างเดียว ไม่ navigate
          CoolerAlert.show(
            context,
            title: msg.contains('Cancel')
                ? 'เอกสารถูกยกเลิก'
                : msg.contains('เสร็จสิ้น')
                ? 'งานเสร็จสิ้นแล้ว'
                : 'เอกสารถูกปิดการใช้งาน',
            message: msg.isNotEmpty
                ? msg
                : 'เอกสารนี้ไม่สามารถใช้งานได้ กรุณาติดต่อ Admin',
            type: CoolerAlertType.error,
            duration: const Duration(seconds: 2),
          );
          return;
        } else {
          CoolerAlert.show(
            context,
            message:
                lookupBody['message']?.toString() ??
                'เกิดข้อผิดพลาด กรุณาลองใหม่',
            type: CoolerAlertType.error,
          );
          return;
        }
      }

      // ✅ is_finished=true → งานเสร็จจาก STA007 → alert แล้วเด้งไป Summary
      if (lookupBody['is_finished'] == true) {
        final msg = lookupBody['message']?.toString() ?? 'เสร็จงานเรียบร้อย';
        final tkIdF = lookupBody['tk_id']?.toString() ?? '';
        CoolerAlert.show(
          context,
          title: 'งานเสร็จสิ้นแล้ว',
          message: msg,
          type: CoolerAlertType.success,
          duration: const Duration(seconds: 2),
        );
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        if (tkIdF.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SummaryPage(tkId: tkIdF)),
          );
        }
        return;
      }

      // ── step 2: ดึง summary ด้วย tk_id ที่ resolve ได้ ──────
      final tkId = lookupBody['tk_id']?.toString() ?? '';
      final summaryRes = await ApiService.getSummaryByTkId(tkId);
      final summaryBody = jsonDecode(summaryRes.body) as Map<String, dynamic>;

      if (!mounted) return;

      if (summaryRes.statusCode == 200) {
        // เช็ค Cancel ก่อน navigate
        if (summaryBody['tk_status'] == 4) {
          CoolerAlert.show(
            context,
            title: 'เอกสารถูกยกเลิก',
            message: 'เอกสาร Tracking No. นี้ถูก Cancel ไปแล้ว',
            type: CoolerAlertType.error,
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SummaryPage(tkId: tkId, finishResult: summaryBody),
            ),
          );
        }
      } else {
        final rawMsg = summaryBody['message']?.toString() ?? 'เกิดข้อผิดพลาด';
        CoolerAlert.show(
          context,
          title: summaryRes.statusCode == 404
              ? 'ไม่พบข้อมูล'
              : 'เกิดข้อผิดพลาด',
          message: rawMsg,
          type: summaryRes.statusCode == 404
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
      _lotCtrl.text = result;
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
            onPressed: _loading ? null : () => _lotCtrl.clear(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Search field + QR button ──
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
                      'สแกน / กรอก Lot No.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _lotCtrl,
                      decoration: InputDecoration(
                        hintText: 'กรุณากรอก Lot No.',
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
// QR Scanner Page
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
        title: const Text('Scan Lot No. QR'),
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
                border: Border.all(color: Colors.blueAccent, width: 3),
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
                'Align the Lot No. QR inside the box',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          const Align(
            alignment: Alignment(0, 0.92),
            child: Text(
              '( สแกน Lot No. QR Code )',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
