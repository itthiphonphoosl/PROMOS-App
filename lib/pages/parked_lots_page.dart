import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_service.dart';
import '../widgets/cooler_alert.dart';
import 'summary_page.dart';

class ParkedLotsPage extends StatefulWidget {
  const ParkedLotsPage({super.key});

  @override
  State<ParkedLotsPage> createState() => _ParkedLotsPageState();
}

class _ParkedLotsPageState extends State<ParkedLotsPage> {
  List<Map<String, dynamic>> _lots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getParkedLots();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        setState(() {
          // ✅ deduplicate by parked_lot_no — เก็บ row ที่มี transfer_id สูงสุด (ล่าสุด) เท่านั้น
          final rawLots = (body['parked_lots'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final dedupMap = <String, Map<String, dynamic>>{};
          for (final lot in rawLots) {
            final key =
                lot['parked_lot_no']?.toString() ??
                lot['to_lot_no']?.toString() ??
                '';
            if (key.isEmpty) continue;
            final existing = dedupMap[key];
            if (existing == null) {
              dedupMap[key] = lot;
            } else {
              final newId =
                  int.tryParse(lot['transfer_id']?.toString() ?? '0') ?? 0;
              final oldId =
                  int.tryParse(existing['transfer_id']?.toString() ?? '0') ?? 0;
              if (newId > oldId) dedupMap[key] = lot;
            }
          }
          _lots = dedupMap.values.toList();
        });
      } else if (res.statusCode == 404 ||
          body['message']?.toString().toLowerCase() == 'not found') {
        // ข้อ 4: ถ้าไม่พบ lot พัก → แสดง empty state ปกติ ไม่ต้อง alert
        setState(() => _lots = []);
      } else {
        if (mounted) {
          CoolerAlert.show(
            context,
            message: body['message']?.toString() ?? 'โหลดไม่ได้',
            type: CoolerAlertType.error,
          );
        }
      }
    } catch (_) {
      if (mounted) {
        CoolerAlert.show(
          context,
          message: 'เชื่อมต่อ Server ไม่ได้',
          type: CoolerAlertType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // จัดกลุ่ม lot ตาม tk_id เพื่อให้เห็น TK No. ชัดเจน
  Map<String, List<Map<String, dynamic>>> get _grouped {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final lot in _lots) {
      final tk =
          lot['from_tk_id']?.toString() ?? lot['to_tk_id']?.toString() ?? '-';
      map.putIfAbsent(tk, () => []).add(lot);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: const Text('Lot ที่พักไว้'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lots.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ไม่มี Lot ที่พักอยู่',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Station นี้ไม่มี Lot รอดำเนินการ',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // header summary
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.blue,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'พบ ${_lots.length} Lot จาก ${grouped.length} เอกสาร',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // กลุ่มตาม TK
                  ...grouped.entries.map((entry) {
                    final tkId = entry.key;
                    final items = entry.value;
                    final firstSta =
                        items.first['op_sta_id']?.toString() ?? '-';
                    final firstStaName =
                        items.first['op_sta_name']?.toString() ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // TK header
                          InkWell(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SummaryPage(tkId: tkId),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.description_outlined,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tkId,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.location_on_outlined,
                                              color: Colors.white70,
                                              size: 12,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              firstStaName.isNotEmpty
                                                  ? '$firstSta  •  $firstStaName'
                                                  : firstSta,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // lot rows
                          ...items.asMap().entries.map((e) {
                            final i = e.key;
                            final lot = e.value;
                            final isLast = i == items.length - 1;
                            final lotNo =
                                lot['parked_lot_no']?.toString() ?? '-';
                            final qty = lot['parked_qty']?.toString() ?? '-';
                            final reason =
                                lot['parked_reason']?.toString() ?? '-';
                            final parkedAt = _formatDate(
                              lot['parked_at']?.toString(),
                            );
                            final camFrom =
                                lot['came_from_lot']?.toString() ?? '-';

                            return Container(
                              decoration: BoxDecoration(
                                border: !isLast
                                    ? Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      )
                                    : null,
                                borderRadius: isLast
                                    ? const BorderRadius.vertical(
                                        bottom: Radius.circular(12),
                                      )
                                    : null,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.pause_circle_outline,
                                      color: Colors.blue,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          lotNo,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'จาก: $camFrom',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            _Badge(
                                              label: 'Qty: $qty',
                                              color: Colors.blue,
                                            ),
                                            const SizedBox(width: 6),
                                            _Badge(
                                              label: reason,
                                              color: Colors.purple,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'พักเมื่อ: $parkedAt',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
    ),
  );
}
