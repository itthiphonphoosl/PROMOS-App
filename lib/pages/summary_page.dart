import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_service.dart';
import '../widgets/cooler_alert.dart';

class SummaryPage extends StatefulWidget {
  final String tkId;

  /// ถ้าหน้า Finish ส่งผลลัพธ์มา จะเอามาแสดงก่อน แล้วค่อย refresh จาก API ได้
  final Map<String, dynamic>? finishResult;

  const SummaryPage({super.key, required this.tkId, this.finishResult});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  int _runSuffix(String lotNo) {
    final m = RegExp(r'-(\d+)$').firstMatch(lotNo.trim());
    if (m == null) return 1 << 30;
    return int.tryParse(m.group(1)!) ?? (1 << 30);
  }

  int _toInt01(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v.toInt();
    final s = v.toString().trim().toLowerCase();
    if (s == 'true') return 1;
    if (s == 'false') return 0;
    return int.tryParse(s) ?? fallback;
  }

  String _motherLotFromPayload() {
    final lots = _allLotsFromPayload();
    if (lots.isEmpty) return '-';
    lots.sort((a, b) => _runSuffix(a).compareTo(_runSuffix(b)));
    return lots.first; // ✅ lot แม่ = suffix น้อยสุด (เช่น ...000220)
  }

  @override
  void initState() {
    super.initState();
    if (widget.finishResult != null) {
      _data = widget.finishResult;
      _loading = false;
    }
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await ApiService.getSummaryByTkId(widget.tkId);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _data = body;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _loading = false);
        CoolerAlert.show(
          context,
          title: 'โหลด Summary ไม่สำเร็จ',
          message: body['message']?.toString() ?? 'เกิดข้อผิดพลาด',
          type: CoolerAlertType.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      CoolerAlert.show(
        context,
        message: 'เชื่อมต่อ Server ไม่ได้',
        type: CoolerAlertType.error,
      );
    }
  }

  String _tfLabel(dynamic code) {
    final c = int.tryParse(code?.toString() ?? '') ?? 0;
    switch (c) {
      case 1:
        return 'Master';
      case 2:
        return 'Split';
      case 3:
        return 'Co-ID';
      default:
        return '-';
    }
  }

  /// ดึง parked_lots จาก payload
  List<Map<String, dynamic>> _parkedLots() {
    // [FIX] รองรับทั้ง summary API (parked_lots) และ finish result (all_parked_lots)
    final p = _data?['parked_lots'] ?? _data?['all_parked_lots'];
    if (p is List) {
      return p.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// ดึง list scans จาก payload
  List<Map<String, dynamic>> _scans() {
    final s = _data?['scans'];
    if (s is List) {
      return s.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// ดึง list transfers จาก payload
  List<Map<String, dynamic>> _transfers() {
    final t = _data?['transfers'];
    if (t is List) {
      return t.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// กรอง transfers ตาม op_sc_id
  List<Map<String, dynamic>> _transfersByOpSc(String opScId) {
    return _transfers()
        .where((x) => (x['op_sc_id']?.toString() ?? '') == opScId)
        .toList();
  }

  /// รวม lot ทั้งหมดจาก current + transfers (เอาไว้โชว์ "Lots ทั้งหมด" ถ้าต้องการ)
  List<String> _allLotsFromPayload() {
    final set = <String>{};
    final curLot = _data?['current']?['lot_no']?.toString();
    if (curLot != null && curLot.trim().isNotEmpty) set.add(curLot.trim());

    for (final tr in _transfers()) {
      final a = tr['from_lot_no']?.toString() ?? '';
      final b = tr['to_lot_no']?.toString() ?? '';
      if (a.trim().isNotEmpty) set.add(a.trim());
      if (b.trim().isNotEmpty) set.add(b.trim());
    }
    final list = set.toList();
    list.sort();
    return list;
  }

  void _openScanDetail(Map<String, dynamic> scan) {
    final opScId = scan['op_sc_id']?.toString() ?? '';
    final trs = _transfersByOpSc(opScId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'รายละเอียดสแกน • $opScId',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _kv(
                    'Station',
                    '${scan['op_sta_id'] ?? '-'} • ${scan['op_sta_name'] ?? '-'}',
                  ),
                  _kv(
                    'Machine',
                    '${scan['MC_id'] ?? '-'} • ${scan['MC_name'] ?? '-'}',
                  ),
                  _kv('Type', _tfLabel(scan['tf_rs_code'])),
                  _kv(
                    'Good / Scrap',
                    '${scan['op_sc_good_qty'] ?? 0} / ${scan['op_sc_scrap_qty'] ?? 0}',
                  ),
                  _kv('Lot No', scan['lot_no']?.toString() ?? '-'),
                  _kv('Start', scan['op_sc_ts']?.toString() ?? '-'),
                  _kv('Finish', scan['op_sc_finish_ts']?.toString() ?? '-'),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  Text(
                    'รายละเอียดการโอน/แตก/รวม (Transfers) • ${trs.length} รายการ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),

                  if (trs.isEmpty)
                    const Text(
                      'ไม่มี transfer ในสแกนนี้',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ...trs.map((t) {
                      final tf = _tfLabel(t['tf_rs_code']);
                      final fromLot = t['from_lot_no']?.toString() ?? '-';
                      final toLot = t['to_lot_no']?.toString() ?? '-';
                      final qty = t['transfer_qty']?.toString() ?? '0';
                      final ts = t['transfer_ts']?.toString() ?? '-';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      tf,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Qty: $qty',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _kvSmall('From', fromLot),
                              _kvSmall('To', toLot),
                              _kvSmall('Time', ts),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(k, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(child: Text(v.isEmpty ? '-' : v)),
      ],
    ),
  );

  Widget _kvSmall(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            k,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            v.isEmpty ? '-' : v,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final current = (data?['current'] is Map)
        ? Map<String, dynamic>.from(data!['current'] as Map)
        : <String, dynamic>{};
    final scans = _scans();
    final lotsAll = _allLotsFromPayload();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: Text('Summary • ${widget.tkId}'),
        actions: [
          IconButton(onPressed: _fetch, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
          ? const Center(child: Text('ไม่มีข้อมูล'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ───────────────────────────────
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.tkId,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _kv('Part No', current['part_no']?.toString() ?? '-'),
                          _kv(
                            'Part Name',
                            current['part_name']?.toString() ?? '-',
                          ),
                          _kv('Lot No', _motherLotFromPayload()),
                          _kv(
                            'Current Station',
                            current['op_sta_id']?.toString() ?? '-',
                          ),
                          _kv(
                            'Current Machine',
                            current['MC_id']?.toString() ?? '-',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Scan History ─────────────────────────
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
                            'ประวัติการสแกน',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          if (scans.isEmpty)
                            const Text(
                              'ยังไม่มีประวัติ',
                              style: TextStyle(color: Colors.grey),
                            )
                          else
                            ...scans.map((s) {
                              final opScId = s['op_sc_id']?.toString() ?? '';
                              final station =
                                  '${s['op_sta_id'] ?? '-'} • ${s['op_sta_name'] ?? '-'}';
                              final mc = '${s['MC_id'] ?? '-'}';
                              final good = s['op_sc_good_qty'] ?? 0;
                              final scrap = s['op_sc_scrap_qty'] ?? 0;
                              final type = _tfLabel(s['tf_rs_code']);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  onTap: () => _openScanDetail(s),
                                  leading: const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  ),
                                  title: Text(
                                    station,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'SC: $opScId\nMC: $mc | Good: $good | Scrap: $scrap | $type',
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── [FIX] Parked Lots ─────────────────────
                  if (_parkedLots().isNotEmpty) ...[
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.inventory_2_outlined,
                                  color: Colors.blue,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Lot ที่พักอยู่ (${_parkedLots().length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ..._parkedLots().map((pl) {
                              final lotNo =
                                  (pl['parked_lot_no'] ?? pl['lot_no'])
                                      ?.toString() ??
                                  '-';
                              final qty =
                                  (pl['parked_qty'] ?? pl['qty'])?.toString() ??
                                  '-';
                              final sta =
                                  (pl['op_sta_id'] ?? pl['parked_at_sta'])
                                      ?.toString() ??
                                  '-';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.pause_circle_outline,
                                      color: Colors.blue,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            lotNo,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'Station: $sta  •  Qty: $qty',
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
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Lots from payload ─────────────────────
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
                            'Lots ทั้งหมด (จาก summary payload)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          if (lotsAll.isEmpty)
                            const Text(
                              'ยังไม่มี Lot',
                              style: TextStyle(color: Colors.grey),
                            )
                          else
                            ...lotsAll.map(
                              (l) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  l,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
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
    );
  }
}
