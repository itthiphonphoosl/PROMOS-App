import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_service.dart';
import '../widgets/cooler_alert.dart';
import 'scan_finish_page.dart';

class ActiveScanPage extends StatefulWidget {
  const ActiveScanPage({super.key});

  @override
  State<ActiveScanPage> createState() => _ActiveScanPageState();
}

class _ActiveScanPageState extends State<ActiveScanPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _formatDateOnly(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return '-';
    }
  }

  String _formatTimeOnly(String? iso) {
    if (iso == null) return '--:--:--';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final ss = dt.second.toString().padLeft(2, '0');
      return '$hh : $mm : $ss';
    } catch (_) {
      return '--:--:--';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getActiveScans();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        setState(() {
          _items =
              (body['items'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [];
        });
      } else {
        CoolerAlert.show(
          context,
          message: body['message']?.toString() ?? 'โหลดไม่ได้',
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goFinish(Map<String, dynamic> item) async {
    final tkId = item['tk_id']?.toString() ?? '';
    final opScId = item['op_sc_id']?.toString() ?? '';

    try {
      final res = await ApiService.getActiveScanByTkId(tkId);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final lots =
          (body['current_lots'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScanFinishPage(
            opScId: opScId,
            tkId: tkId,
            // [FIX] ใช้ field จาก active scan item ที่ถูกต้อง
            // lot_no ≠ part_no — part_no อยู่ใน tk_doc หรือ detail
            tkDoc: {
              'part_no': item['part_no']?.toString() ?? '',
              'part_name': item['part_name']?.toString() ?? '',
              'op_sta_id': item['op_sta_id']?.toString() ?? '',
              'op_sta_name': item['op_sta_name']?.toString() ?? '',
              'MC_id': item['MC_id']?.toString() ?? '',
              'MC_name': item['MC_name']?.toString() ?? '',
            },
            allLots: lots,
          ),
        ),
      );
    } catch (_) {
      CoolerAlert.show(
        context,
        message: 'เชื่อมต่อ Server ไม่ได้',
        type: CoolerAlertType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        title: const Text('งานที่กำลังทำอยู่'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'ไม่มีงานที่ค้างอยู่',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final item = _items[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _goFinish(item), // ✅ กดตรงไหนก็ไปหน้า Finish
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: const Border(
                          left: BorderSide(
                            width: 6,
                            color: Colors.orange,
                          ), // แถบส้มซ้าย
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── แถวบน: TK ซ้าย / วันที่ขวาสุด ──
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item['tk_id']?.toString() ?? '-',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDateOnly(item['op_sc_ts']?.toString()),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // ── รายละเอียด ──
                          Text(
                            'SC : ${item['op_sc_id'] ?? '-'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'STA : ${item['op_sta_id'] ?? '-'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MC : ${item['MC_id'] ?? '-'}',
                            style: const TextStyle(fontSize: 12),
                          ),

                          // ✅ เวลาเริ่ม + ปุ่ม Finish (อยู่แถวเดียวกัน)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'เวลาเริ่ม: ${_formatTimeOnly(item['op_sc_ts']?.toString())}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 32,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () => _goFinish(item),
                                  child: const Text(
                                    'Finish',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
