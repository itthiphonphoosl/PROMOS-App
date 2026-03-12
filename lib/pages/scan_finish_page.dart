import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_service.dart';
import '../widgets/cooler_alert.dart';
import 'summary_page.dart';

class ScanFinishPage extends StatefulWidget {
  final String opScId;
  final String tkId;
  final Map<String, dynamic> tkDoc;
  final List<Map<String, dynamic>> allLots;

  const ScanFinishPage({
    super.key,
    required this.opScId,
    required this.tkId,
    required this.tkDoc,
    required this.allLots,
  });

  @override
  State<ScanFinishPage> createState() => _ScanFinishPageState();
}

class _ScanFinishPageState extends State<ScanFinishPage> {
  final _goodCtrl = TextEditingController();
  final _scrapCtrl = TextEditingController();

  final List<_GroupEntry> _groups = [];
  bool _finishing = false;

  String? _baseLotNo;
  List<String> _currentLots = [];
  bool _loadingLots = true;

  List<Map<String, dynamic>> _parkedLots = [];

  // ✅ Cross-TK parked lots: lot ที่พักจาก TK อื่นแต่อยู่ที่ station เดียวกัน
  Map<String, String> _crossTkLotMap = {}; // lot_no → source_tk_id
  List<Map<String, dynamic>> _crossTkParkedLots = [];

  String? _staId;
  String? _staName;
  String? _mcId;
  String? _mcName;

  // ✅ part_no default = part ล่าสุดที่ finish หรือ part ที่มากับเอกสาร
  String? _defaultPartNo;

  // ✅ เคย transfer มาแล้ว → เปิดใช้ parked lot ใน From Lot
  bool _hasTransferHistory = false;

  // ตัดเอาเฉพาะ part_no จริง — ถ้าขึ้นด้วย 6 หลักตามด้วย - = lot, return ''
  String _extractPartNoOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    if (RegExp(r'^\d{6}-').hasMatch(s)) return '';
    return s;
  }

  bool _isParked(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    final s = v.toString().trim().toLowerCase();
    return s == '1' || s == 'true';
  }

  // [FIX] เพิ่ม _toInt01 — ถูกเรียกใน _loadCurrentLotsFromSummary แต่ไม่เคย define ไว้
  int _toInt01(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v.toInt();
    final s = v.toString().trim().toLowerCase();
    if (s == 'true') return 1;
    if (s == 'false') return 0;
    return int.tryParse(s) ?? fallback;
  }

  int _runSuffix(String lotNo) {
    final m = RegExp(r'-(\d+)$').firstMatch(lotNo.trim());
    if (m == null) return 1 << 30;
    return int.tryParse(m.group(1)!) ?? (1 << 30);
  }

  String? _pickBaseLotFromAllLots() {
    final all = widget.allLots
        .map((x) => (x['lot_no']?.toString() ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (all.isEmpty) return null;
    all.sort((a, b) => _runSuffix(a).compareTo(_runSuffix(b)));
    return all.first;
  }

  Future<void> _loadCurrentLotsFromSummary() async {
    try {
      final res = await ApiService.getSummaryByTkId(widget.tkId);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200) {
        // 1) base lot
        final baseLotNoDirect = (body['base_lot_no']?.toString() ?? '').trim();
        final baseMap = (body['base'] as Map?)?.cast<String, dynamic>();
        final baseLotNoFromObj = (baseMap?['lot_no']?.toString() ?? '').trim();
        final baseLot = baseLotNoDirect.isNotEmpty
            ? baseLotNoDirect
            : (baseLotNoFromObj.isNotEmpty ? baseLotNoFromObj : '');
        if (baseLot.isNotEmpty)
          _baseLotNo = baseLot;
        else
          _baseLotNo ??= _pickBaseLotFromAllLots();

        // 2) machine / station
        final scans = (body['scans'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        Map<String, dynamic>? activeScan;
        for (final s in scans.reversed) {
          final ft = s['op_sc_finish_ts'];
          if (ft == null || ft.toString().trim().isEmpty) {
            activeScan = s;
            break;
          }
        }
        final current = (body['current'] as Map?)?.cast<String, dynamic>();
        _staId =
            (activeScan?['op_sta_id']?.toString() ??
                    current?['op_sta_id']?.toString() ??
                    '')
                .trim();
        _staName = (activeScan?['op_sta_name']?.toString() ?? '').trim();
        _mcId =
            (activeScan?['MC_id']?.toString() ??
                    current?['MC_id']?.toString() ??
                    '')
                .trim();
        _mcName = (activeScan?['MC_name']?.toString() ?? '').trim();

        // 3) leaf lots (active only)
        final transfers = (body['transfers'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        String? latestTs;
        for (final t in transfers) {
          final ts = t['transfer_ts']?.toString() ?? '';
          if (ts.isNotEmpty &&
              (latestTs == null || ts.compareTo(latestTs!) > 0)) {
            latestTs = ts;
          }
        }
        final latestBatch = latestTs == null
            ? transfers
            : transfers
                  .where((t) => t['transfer_ts']?.toString() == latestTs)
                  .toList();
        final activeToSet = <String>{};
        for (final t in latestBatch) {
          final tl = (t['to_lot_no']?.toString() ?? '').trim();
          final isParked = _toInt01(t['lot_parked_status']) == 1;
          if (tl.isNotEmpty && !isParked) activeToSet.add(tl);
        }
        final leaf = activeToSet.where((x) => x.isNotEmpty).toList()
          ..sort((a, b) => _runSuffix(a).compareTo(_runSuffix(b)));

        // 4) parked lots — กรองเฉพาะ lot ที่พักใน station ของ operator ปัจจุบัน
        final currentStaId = _staId?.trim() ?? '';
        final parkedFromSummary = (body['parked_lots'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((p) {
              final lotSta = p['op_sta_id']?.toString().trim() ?? '';
              return currentStaId.isEmpty || lotSta == currentStaId;
            })
            .toList();

        // ✅ Cross-TK: โหลด lot ที่พักจาก TK อื่นใน station เดียวกัน
        final stationAllRaw = (body['parked_lots_station_all'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final crossTkMap = <String, String>{};
        final crossTkParkedList = <Map<String, dynamic>>[];
        for (final p in stationAllRaw) {
          final lotNo = p['parked_lot_no']?.toString() ?? '';
          final srcTk = p['from_tk_id']?.toString() ?? '';
          if (lotNo.isEmpty || srcTk.isEmpty) continue;
          if (srcTk != widget.tkId) {
            // เป็น lot จาก TK อื่น
            if (!crossTkMap.containsKey(lotNo)) {
              crossTkMap[lotNo] = srcTk;
              crossTkParkedList.add(p);
            }
          }
        }

        // 5) ✅ default part_no — เอาแค่ part_no จริงๆ ไม่เอา lot number
        //    ลำดับ: out_part_no จาก transfer ล่าสุด → current.part_no → tkDoc.part_no
        //    ✅ _hasTransferHistory = เคย transfer มาแล้ว (tf_rs_code != 0 / transfers ไม่ว่าง)
        final hasTransferHistory = transfers.isNotEmpty;

        String? lastPartNo;
        if (hasTransferHistory) {
          for (final t in transfers.reversed) {
            final pNo = _extractPartNoOnly(t['out_part_no']?.toString() ?? '');
            if (pNo.isNotEmpty) {
              lastPartNo = pNo;
              break;
            }
          }
        }
        // fallback → current.part_no (เป็น part_no จริง ไม่ใช่ lot)
        if (lastPartNo == null || lastPartNo!.isEmpty) {
          lastPartNo = _extractPartNoOnly(
            current?['part_no']?.toString() ?? '',
          );
        }
        // fallback → tkDoc.part_no
        if (lastPartNo == null || lastPartNo!.isEmpty) {
          lastPartNo = _extractPartNoOnly(
            widget.tkDoc['part_no']?.toString() ?? '',
          );
        }

        if (!mounted) return;
        setState(() {
          _currentLots = leaf.isNotEmpty
              ? leaf
              : (_baseLotNo != null ? [_baseLotNo!] : []);
          _parkedLots = parkedFromSummary;
          _crossTkLotMap = crossTkMap;
          _crossTkParkedLots = crossTkParkedList;
          _defaultPartNo = lastPartNo;
          _hasTransferHistory = hasTransferHistory;
          _loadingLots = false;
        });
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _baseLotNo ??= _pickBaseLotFromAllLots();
      _currentLots = _baseLotNo != null ? [_baseLotNo!] : [];
      _parkedLots = [];
      _crossTkLotMap = {};
      _crossTkParkedLots = [];
      _defaultPartNo = _extractPartNoOnly(
        widget.tkDoc['part_no']?.toString() ?? '',
      );
      _hasTransferHistory = false;
      _loadingLots = false;
    });
  }

  List<Map<String, dynamic>> _parts = [];
  bool _loadingParts = true;
  List<Map<String, dynamic>> _colors = [];

  int _goodQty() => int.tryParse(_goodCtrl.text.trim()) ?? 0;
  int _sumGroupQty() =>
      _groups.fold(0, (a, g) => a + (int.tryParse(g.qtyCtrl.text.trim()) ?? 0));
  int _remainingGood() => _goodQty() - _sumGroupQty();
  // ✅ isFirstScan = ยังไม่เคย transfer เลย → lock From Lot, ไม่ใช้ parked
  bool get _isFirstScan => !_hasTransferHistory;

  @override
  void initState() {
    super.initState();
    _loadParts();
    _loadColors();
    _loadCurrentLotsFromSummary();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _ensureOneGroup());
    });
  }

  bool get _isSimpleFlow {
    final lots = _currentLots.where((s) => s.trim().isNotEmpty).toList();
    // ข้อ 2: ถ้าเป็น first scan (tf=0, ยังไม่เคย transfer เลย)
    //         → มี lot เดียวเสมอ → ห้ามเพิ่ม group ไม่ว่าจะมี parked lots จาก TK อื่นหรือเปล่า
    if (_isFirstScan) return true;
    // ถ้าเคย transfer แล้ว → ดูจำนวน active lots + parked lots รวมกัน
    return lots.length <= 1 &&
        !(_parkedLots.isNotEmpty || _crossTkParkedLots.isNotEmpty);
  }

  void _ensureOneGroup() {
    if (_groups.isEmpty) _groups.add(_GroupEntry());
  }

  Future<void> _loadParts() async {
    try {
      final res = await ApiService.getParts();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        setState(() {
          _parts = (body['parts'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingParts = false);
  }

  Future<void> _loadColors() async {
    try {
      final res = await ApiService.getColors();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && mounted) {
        // รองรับทั้ง { colors: [...] } และ { items: [...] }
        final raw = body['colors'] ?? body['items'] ?? body['data'] ?? [];
        setState(() {
          _colors = (raw as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _goodCtrl.dispose();
    _scrapCtrl.dispose();
    super.dispose();
  }

  void _addGroup() {
    final remaining = _remainingGood();
    // [FIX] ไม่ block — เพิ่ม group ได้เสมอถ้ามี lot มากกว่า 1
    // ถ้า remaining > 0 → pre-fill qty ให้, ถ้าไม่มี → ปล่อยว่างให้กรอกเอง
    final entry = _GroupEntry()
      ..qtyCtrl.text = remaining > 0 ? remaining.toString() : '';
    entry.defaultPartNo = _defaultPartNo;
    setState(() => _groups.add(entry));
  }

  void _removeGroup(int i) => setState(() => _groups.removeAt(i));

  Future<void> _finish() async {
    final goodRaw = int.tryParse(_goodCtrl.text.trim());
    final scrapRaw = int.tryParse(_scrapCtrl.text.trim());

    if (goodRaw == null || scrapRaw == null) {
      CoolerAlert.show(
        context,
        message: 'กรุณากรอก จำนวน OK และ จำนวน NG เป็นตัวเลข',
        type: CoolerAlertType.warning,
      );
      return;
    }
    final good = goodRaw.abs();
    final scrap = scrapRaw.abs();

    if (good == 0 && scrap == 0) {
      CoolerAlert.show(
        context,
        message: 'จำนวน OK และ NG ห้ามเป็น 0 พร้อมกัน',
        type: CoolerAlertType.warning,
      );
      return;
    }
    if (_groups.isEmpty) {
      CoolerAlert.show(
        context,
        message: 'กรุณาเพิ่มอย่างน้อย 1 Group',
        type: CoolerAlertType.warning,
      );
      return;
    }

    final sumGroupQty = _groups.fold(
      0,
      (a, g) => a + ((int.tryParse(g.qtyCtrl.text.trim()) ?? 0).abs()),
    );
    final hasSplitGroup = _groups.any((g) => g.tfRsCode == 2);

    if (!hasSplitGroup && sumGroupQty != good) {
      CoolerAlert.show(
        context,
        message:
            'รวม qty ทุก Group ($sumGroupQty) ต้องเท่ากับ จำนวน OK ($good) พอดี',
        type: CoolerAlertType.warning,
      );
      return;
    }
    if (hasSplitGroup && sumGroupQty > good) {
      CoolerAlert.show(
        context,
        message: 'รวม qty ทุก Group ($sumGroupQty) เกิน จำนวน OK ($good)',
        type: CoolerAlertType.warning,
      );
      return;
    }

    for (int i = 0; i < _groups.length; i++) {
      final err = _groups[i].validate();
      if (err != null) {
        CoolerAlert.show(
          context,
          message: 'Group ${i + 1}: $err',
          type: CoolerAlertType.warning,
        );
        return;
      }
    }
    // ข้อ 3: ตรวจหา active lots ที่ไม่ถูกเลือกเป็น from_lot → จะถูก auto-park
    //   เฉพาะ active lots เท่านั้น (parked lots ไม่นับ เพราะถ้าไม่เลือกก็ยังพักอยู่เหมือนเดิม)
    final selectedFromLots = <String>{};
    for (final g in _groups) {
      if (g.fromLotNo != null && g.fromLotNo!.isNotEmpty) {
        selectedFromLots.add(g.fromLotNo!);
      } else if (_isFirstScan && _currentLots.length == 1) {
        // [FIX] isFirstScan + lot เดียว → ล็อคอัตโนมัติ
        // g.fromLotNo อาจเป็น null ถ้า _autoLockFromLot() วิ่งก่อน lots โหลดเสร็จ
        // → ถือว่า lot นั้นถูกเลือกอยู่แล้ว ไม่ต้อง auto-park
        selectedFromLots.add(_currentLots.first);
      }
      for (final m in g.mergeLots) {
        if (m.fromLotNo != null && m.fromLotNo!.isNotEmpty) {
          selectedFromLots.add(m.fromLotNo!);
        }
      }
    }
    final willBeParked = _currentLots
        .where((l) => l.trim().isNotEmpty && !selectedFromLots.contains(l))
        .toList();

    if (willBeParked.isNotEmpty) {
      // แสดง dialog ยืนยันก่อน
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFE67E22).withOpacity(0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF39C12).withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF39C12),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF39C12),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFF39C12,
                                  ).withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Lot ที่จะถูกพักอัตโนมัติ',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF39C12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Lot ต่อไปนี้ไม่ได้ถูกเลือก จะถูกพักไว้อัตโนมัติ:',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...willBeParked.map(
                        (l) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFFFD700).withOpacity(0.6),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.pause_circle_outline,
                                color: Color(0xFFF39C12),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2D3436),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'ต้องการดำเนินการต่อหรือไม่?',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('ยกเลิก'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF39C12),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'ตกลง พักไว้',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
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
      );

      if (confirmed != true) {
        if (mounted) setState(() => _finishing = false);
        return; // user กด ยกเลิก → กลับไปแก้ไข
      }
    }

    // ── ตรวจ tf=2 groups ที่ splits ไม่ครบ qty → จะพักส่วนที่เหลือ ──
    final splitParkInfo = <Map<String, dynamic>>[];
    for (int i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      if (g.tfRsCode != 2) continue;
      final gQty = int.tryParse(g.qtyCtrl.text.trim()) ?? 0;
      final splitSum = g.splits.fold(
        0,
        (a, s) => a + (int.tryParse(s.qtyCtrl.text.trim()) ?? 0),
      );
      final diff = gQty - splitSum;
      if (diff > 0) {
        final lotNo =
            g.fromLotNo ??
            (_isFirstScan && _currentLots.length == 1
                ? _currentLots.first
                : null);
        splitParkInfo.add({
          'group': i + 1,
          'lot': lotNo ?? '(ไม่ระบุ lot)',
          'diff': diff,
          'gQty': gQty,
          'splitSum': splitSum,
        });
      }
    }

    if (splitParkInfo.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFE67E22).withOpacity(0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF39C12).withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // แถบสีบน
                Container(
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF39C12),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // header row
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF39C12),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFF39C12,
                                  ).withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Lot ที่จะถูกพักอัตโนมัติ',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF39C12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Lot ต่อไปนี้ไม่ได้ถูกเลือก จะถูกพักไว้อัตโนมัติ:',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // lot cards
                      ...splitParkInfo.map(
                        (info) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFFFD700).withOpacity(0.6),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.pause_circle_outline,
                                color: Color(0xFFF39C12),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      info['lot'] as String,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2D3436),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Group ${info['group']}: จะพัก ${info['diff']} ชิ้น (splits ไม่ครบ qty)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'ต้องการดำเนินการต่อหรือไม่?',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('ยกเลิก'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF39C12),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'ตกลง พักไว้',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
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
      );
      if (confirmed != true) return;
    }

    setState(() => _finishing = true);
    try {
      final res = await ApiService.finishScan(
        opScId: widget.opScId,
        goodQty: good,
        scrapQty: scrap,
        groups: _groups.map((g) => g.toJson()).toList(),
        // ✅ color_id ตอนนี้อยู่ใน groups แต่ละตัวแล้ว (per-group / per-split)
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200) {
        final isFinished = body['is_finished'] == true;
        final autoParkedCount = (body['auto_parked_count'] ?? 0) as int;
        final createdGroups = (body['created_groups'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((g) => g['group'].toString() != 'auto_park')
            .toList();

        String tfLabel(dynamic tf) {
          switch (int.tryParse(tf?.toString() ?? '') ?? 0) {
            case 1:
              return 'Master-ID';
            case 2:
              return 'Split-ID';
            case 3:
              return 'Co-ID';
            default:
              return '-';
          }
        }

        final groupLines = createdGroups
            .asMap()
            .entries
            .map((e) {
              final idx = e.key + 1;
              final g = e.value;
              final lbl = tfLabel(g['tf_rs_code']);
              final pLots = (g['parked_lots'] as List? ?? []);
              final pNote = pLots.isNotEmpty ? '  🔵 พัก ${pLots.length}' : '';
              return 'Group $idx : $lbl$pNote';
            })
            .join('\n');

        final msgLines = [
          groupLines,
          if (autoParkedCount > 0)
            '🔵 Auto-พัก $autoParkedCount lot (ไม่ได้ใช้งาน)',
        ].join('\n');

        CoolerAlert.show(
          context,
          title: isFinished
              ? 'Finish Station สุดท้ายสำเร็จ!'
              : 'Finish สำเร็จ!',
          message: msgLines,
          type: CoolerAlertType.success,
          duration: const Duration(seconds: 1),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => SummaryPage(tkId: widget.tkId, finishResult: body),
          ),
          (r) => r.isFirst,
        );
      } else {
        CoolerAlert.show(
          context,
          title: 'Finish ไม่สำเร็จ',
          message: body['message']?.toString() ?? 'เกิดข้อผิดพลาด',
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
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  // ── Pre-Finish Summary Box ──
  Widget _buildPreFinishSummary() {
    final good = _goodQty();
    final total = good + (int.tryParse(_scrapCtrl.text.trim()) ?? 0);
    final sumGrp = _sumGroupQty();
    final remain = good - sumGrp;
    final isOver = remain < 0;
    final isExact = remain == 0 && good > 0;

    // Per-group park preview (tf=2 only)
    final groupParkLines = <String>[];
    for (int i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      if (g.tfRsCode != 2) continue;
      final gQty = int.tryParse(g.qtyCtrl.text.trim()) ?? 0;
      final splitSum = g.splits.fold(
        0,
        (a, s) => a + (int.tryParse(s.qtyCtrl.text.trim()) ?? 0),
      );
      final diff = gQty - splitSum;
      if (diff > 0) {
        groupParkLines.add(
          'Group ${i + 1}: Split รวม $splitSum / $gQty  →  จะพัก $diff ชิ้น',
        );
      }
    }

    // มี tf=2 group ไหม → ถึงจะพักอัตโนมัติ
    final hasSplitGroup = _groups.any((g) => g.tfRsCode == 2);

    final Color borderColor;
    final Color bgColor;
    if (isOver) {
      borderColor = Colors.red.shade300;
      bgColor = Colors.red.shade50;
    } else if (groupParkLines.isNotEmpty) {
      borderColor = Colors.blue.shade300;
      bgColor = Colors.blue.shade50;
    } else if (isExact) {
      borderColor = Colors.green.shade300;
      bgColor = Colors.green.shade50;
    } else {
      borderColor = Colors.orange.shade300;
      bgColor = Colors.orange.shade50;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total qty (OK + NG) = $total',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Sum Group qty = $sumGrp  (ต้องเท่ากับ จำนวน OK = $good)',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            isOver
                ? '⚠️ เกิน จำนวน OK ${remain.abs()} ชิ้น'
                : isExact && groupParkLines.isEmpty
                ? '✅ ครบพอดี'
                : remain > 0
                ? hasSplitGroup && _groups.length == 1
                      ? '🔵 ยังเหลือ $remain ชิ้น → จะพักอัตโนมัติ'
                      : hasSplitGroup
                      ? '🔵 ยังขาดอีก $remain ชิ้น → ส่วนที่เหลือจะพักอัตโนมัติใน Split Group'
                      : '🔵 ยังขาดอีก $remain ชิ้น'
                : '✅ ครบพอดี',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOver
                  ? Colors.red.shade800
                  : groupParkLines.isNotEmpty
                  ? Colors.blue.shade800
                  : isExact
                  ? Colors.green.shade800
                  : Colors.orange.shade800,
            ),
          ),
          // Per-group park warnings
          if (groupParkLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            const Text(
              '📦 Lot ที่จะพักตาม Group:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            ...groupParkLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 7, color: Colors.blue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget build(BuildContext context) {
    final lots = _currentLots;
    // [FIX] ให้เพิ่ม Group ได้เลยถ้ามี lot มากกว่า 1
    // ไม่ต้องรอกรอก good_qty ก่อน — validate ที่ปุ่ม Finish แทน
    final canAddGroup = !_isSimpleFlow;
    final isQtyFull = _goodQty() > 0 && _remainingGood() <= 0;
    final parkedLotNos = _parkedLots
        .map((pl) => pl['parked_lot_no']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    // ✅ cross-TK lot nos (จาก TK อื่นที่พักอยู่ใน station เดียวกัน)
    final crossTkLotNos = _crossTkParkedLots
        .map((pl) => pl['parked_lot_no']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    // ข้อ 1: parked lots (own + cross-TK) ใช้ได้เฉพาะ CO-ID (tf=3) เท่านั้น
    // Master-ID (tf=1) และ Split-ID (tf=2) ใช้เฉพาะ active lots ของ TK ตัวเอง
    // ดังนั้น allAvailableLots = active lots เสมอ
    // → _GroupCard จะรับ parkedLotNos/crossTkLotNos แยกต่างหาก
    //   แล้วรวมเข้าไปเฉพาะเมื่อ tfRsCode == 3 (ดูใน _GroupCard)
    //
    // [DISABLED - เดิมรวม parked lots ให้ทุก tf แต่ requirement บอกแค่ CO-ID]
    // final allAvailableLots = [
    //   ...(_hasTransferHistory ? [...lots, ...parkedLotNos] : lots),
    //   ...crossTkLotNos,
    // ];
    final allAvailableLots = List<String>.from(lots); // active lots เท่านั้น

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        title: Text('Finish • ${widget.opScId}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Info Card ──
            _InfoCard(
              tkId: widget.tkId,
              tkDoc: widget.tkDoc,
              baseLotNo: _baseLotNo,
              currentLots: lots,
              stationId: _staId,
              stationName: _staName,
              machineId: _mcId,
              machineName: _mcName,
            ),
            const SizedBox(height: 16),

            // ── จำนวน OK / NG ──
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
                      'จำนวน',
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
                            controller: _goodCtrl,
                            decoration: const InputDecoration(
                              labelText: 'จำนวน OK ✅',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) {
                              setState(() {
                                _ensureOneGroup();
                                if (_groups.length == 1) {
                                  _groups[0].qtyCtrl.text = _goodQty()
                                      .abs()
                                      .toString();
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _scrapCtrl,
                            decoration: const InputDecoration(
                              labelText: 'จำนวน NG ❌',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    // indicator
                    Builder(
                      builder: (ctx) {
                        final g = (int.tryParse(_goodCtrl.text.trim()) ?? 0)
                            .abs();
                        final s = (int.tryParse(_scrapCtrl.text.trim()) ?? 0)
                            .abs();
                        final total = g + s;
                        final sumGrp = _groups.fold(
                          0,
                          (a, x) =>
                              a +
                              ((int.tryParse(x.qtyCtrl.text.trim()) ?? 0)
                                  .abs()),
                        );
                        final remain = g - sumGrp;

                        // แสดง indicator เฉพาะเมื่อมี group มากกว่า 1
                        if (_groups.length <= 1) return const SizedBox.shrink();

                        if (total <= 0 && sumGrp <= 0)
                          return const SizedBox.shrink();

                        final isOver = remain < 0;
                        final hasSplit = _groups.any((g) => g.tfRsCode == 2);
                        final isParked = remain > 0 && hasSplit;
                        final isShort = remain > 0 && !hasSplit;

                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isOver
                                  ? Colors.red.shade50
                                  : isShort
                                  ? Colors.orange.shade50
                                  : isParked
                                  ? Colors.blue.shade50
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isOver
                                    ? Colors.red.shade200
                                    : isShort
                                    ? Colors.orange.shade200
                                    : isParked
                                    ? Colors.blue.shade200
                                    : Colors.green.shade200,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total qty (OK + NG) = $total',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hasSplit
                                      ? 'Sum Group qty = $sumGrp  (ต้องไม่เกิน จำนวน OK = $g)'
                                      : 'Sum Group qty = $sumGrp  (ต้องเท่ากับ จำนวน OK = $g)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isOver
                                      ? '⚠️ เกิน จำนวน OK ${remain.abs()} ชิ้น'
                                      : isShort
                                      ? '⚠️ ยังขาดอีก $remain ชิ้น (ต้องครบ $g)'
                                      : isParked
                                      ? '🔵 จะพักอัตโนมัติ $remain ชิ้น'
                                      : '✅ ครบพอดี',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isOver
                                        ? Colors.red.shade800
                                        : isShort
                                        ? Colors.orange.shade800
                                        : isParked
                                        ? Colors.blue.shade800
                                        : Colors.green.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Loading indicators ──
            if (_loadingLots)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'กำลังโหลด Lots...',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            if (_loadingParts)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'กำลังโหลดรายการ Part...',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),

            // ── ✅ Parked Lots inline section (own-TK + cross-TK) ──
            if (_parkedLots.isNotEmpty || _crossTkParkedLots.isNotEmpty) ...[
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
                      const Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.blue,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Lot ที่พักไว้ใน Station นี้',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // scroll when total > 3
                      Builder(
                        builder: (context) {
                          final allTiles = [
                            ..._parkedLots.map(
                              (pl) => _ParkedLotTile(
                                lotNo: pl['parked_lot_no']?.toString() ?? '',
                                qty: pl['parked_qty']?.toString() ?? '-',
                                reason: pl['parked_reason']?.toString() ?? '',
                                tkId: pl['from_tk_id']?.toString() ?? '-',
                                sta: pl['op_sta_id']?.toString() ?? '-',
                                staName: pl['op_sta_name']?.toString() ?? '',
                                isCrossTk: false,
                              ),
                            ),
                          ];
                          final hasCross = _crossTkParkedLots.isNotEmpty;
                          final crossTiles = hasCross
                              ? _crossTkParkedLots
                                    .map(
                                      (pl) => _ParkedLotTile(
                                        lotNo:
                                            pl['parked_lot_no']?.toString() ??
                                            '',
                                        qty:
                                            pl['parked_qty']?.toString() ?? '-',
                                        reason:
                                            pl['parked_reason']?.toString() ??
                                            '',
                                        tkId:
                                            pl['from_tk_id']?.toString() ?? '-',
                                        sta: pl['op_sta_id']?.toString() ?? '-',
                                        staName:
                                            pl['op_sta_name']?.toString() ?? '',
                                        isCrossTk: true,
                                      ),
                                    )
                                    .toList()
                              : <Widget>[];

                          final totalCount =
                              allTiles.length + crossTiles.length;
                          final needsScroll = totalCount > 3;

                          Widget buildContent() => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...allTiles,
                              if (hasCross) ...[
                                const Divider(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.swap_horiz,
                                      color: Colors.orange.shade700,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Lot จาก TK อื่น (สามารถหยิบมาใช้ได้)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ...crossTiles,
                              ],
                            ],
                          );

                          if (needsScroll) {
                            final _scrollCtrl = ScrollController();
                            return SizedBox(
                              height: 260,
                              child: Scrollbar(
                                thumbVisibility: true,
                                controller: _scrollCtrl,
                                child: SingleChildScrollView(
                                  controller: _scrollCtrl,
                                  child: buildContent(),
                                ),
                              ),
                            );
                          }
                          return buildContent();
                        },
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '💡 Lot ที่พักไว้สามารถเลือกใน From Lot ได้',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Group Cards ──
            ...List.generate(_groups.length, (i) {
              if (_groups[i].defaultPartNo == null && _defaultPartNo != null) {
                final v = _defaultPartNo!;
                _groups[i].defaultPartNo = RegExp(r'^\d{6}-').hasMatch(v)
                    ? null
                    : v;
              }

              // ✅ รวม lot ที่ถูกใช้ใน group อื่นแล้ว (tf=1/2 ใช้ fromLotNo, tf=3 ใช้ mergeLots)
              final usedLots = <String>{};
              for (final e in _groups.asMap().entries) {
                if (e.key == i) continue;
                final g = e.value;
                // tf=1 / tf=2: fromLotNo
                if (g.fromLotNo != null && g.fromLotNo!.isNotEmpty) {
                  usedLots.add(g.fromLotNo!);
                }
                // tf=3: merge lots ทุกตัว
                for (final m in g.mergeLots) {
                  if (m.fromLotNo != null && m.fromLotNo!.isNotEmpty) {
                    usedLots.add(m.fromLotNo!);
                  }
                }
              }
              // ✅ กรอง lot ที่ group ปัจจุบันเลือกไปแล้วใน merge rows อื่น (tf=3 ภายใน group เดียวกัน)
              final selfUsedMergeLots = <String>{};
              if (_groups[i].tfRsCode == 3) {
                for (final m in _groups[i].mergeLots) {
                  if (m.fromLotNo != null && m.fromLotNo!.isNotEmpty) {
                    selfUsedMergeLots.add(m.fromLotNo!);
                  }
                }
              }

              final lotsForThisGroup = allAvailableLots
                  .where((l) => !usedLots.contains(l))
                  .toList();

              return _GroupCard(
                key: ValueKey(i),
                index: i,
                entry: _groups[i],
                availableLots: lotsForThisGroup,
                selfUsedMergeLots: selfUsedMergeLots,
                usedByOtherGroups: usedLots,
                // ข้อ 1: parked lots ส่งแยก — _GroupCard รวมเข้า merge rows เฉพาะ tf=3
                ownParkedLotNos: parkedLotNos,
                crossTkParkedLotNos: crossTkLotNos,
                availableParts: _parts,
                availableColors: _colors, // ✅ STA006
                staId: _staId, // ✅ STA006 check
                isFirstScan: _isFirstScan,
                crossTkLotMap: _crossTkLotMap,
                totalGroups: _groups.length,
                onChanged: () => setState(() {}),
                onRemove: () => _removeGroup(i),
              );
            }),

            OutlinedButton.icon(
              onPressed: canAddGroup ? _addGroup : null,
              icon: const Icon(Icons.add),
              label: Text(
                isQtyFull ? 'เพิ่ม Group (qty ครบแล้ว)' : 'เพิ่ม Group',
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange),
                foregroundColor: Colors.orange,
              ),
            ),
            const SizedBox(height: 16),

            // ── Pre-Finish Summary ──
            _buildPreFinishSummary(),
            const SizedBox(height: 12),

            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _finishing ? null : _finish,
                icon: _finishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _finishing ? 'กำลัง Finish...' : 'Finish งาน',
                  style: const TextStyle(fontSize: 16),
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
// ══════════════════════════════════════════════════════════════════
// ✅ _ParkedLotTile — ใช้ใน ScanFinishPage (own-TK + cross-TK)
// ══════════════════════════════════════════════════════════════════

class _ParkedLotTile extends StatelessWidget {
  final String lotNo;
  final String qty;
  final String reason;
  final String tkId;
  final String sta;
  final String staName;
  final bool isCrossTk;

  const _ParkedLotTile({
    required this.lotNo,
    required this.qty,
    required this.reason,
    required this.tkId,
    required this.sta,
    required this.staName,
    required this.isCrossTk,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isCrossTk
        ? Colors.orange.shade200
        : Colors.blue.shade200;
    final iconColor = isCrossTk ? Colors.orange.shade700 : Colors.blue;
    final icon = isCrossTk ? Icons.swap_horiz : Icons.pause_circle_outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  'TK No. : $tkId  •  Station: ${staName.isNotEmpty ? "$sta ($staName)" : sta}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Text(
                  'Qty: $qty  •  $reason',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                if (isCrossTk)
                  Text(
                    '🔀 เลือกใน From Lot เพื่อดึงมาใช้กับ TK นี้',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Models
// ══════════════════════════════════════════════════════════════════

class _GroupEntry {
  int tfRsCode = 1;
  final qtyCtrl = TextEditingController();

  String? fromLotNo;
  String? outPartNo; // tf=1: out_part_no (group level)
  String?
  outPartNoGroup; // tf=2: out_part_no (group level, สำหรับ parked remainder)
  String? defaultPartNo;
  int? colorId; // STA006 only — group/lot level color

  final List<_SplitEntry> splits = [];

  String? outPartNoMerge;
  final List<_MergeLotEntry> mergeLots = [_MergeLotEntry(), _MergeLotEntry()];

  String? validate() {
    final qty = int.tryParse(qtyCtrl.text.trim());
    if (qty == null || qty <= 0) return 'qty ต้องมากกว่า 0';

    // tf=1 / tf=2: out_part_no ใช้ defaultPartNo อัตโนมัติ → ไม่ต้อง validate ที่นี่

    if (tfRsCode == 2) {
      for (final s in splits) {
        if (s.partNo == null || s.partNo!.isEmpty)
          return 'เลือก Part No ใน split ให้ครบ';
        final q = int.tryParse(s.qtyCtrl.text.trim());
        if (q == null) return 'qty ใน split ต้องเป็นตัวเลข';
        if (q <= 0) return 'qty ใน split ต้องมากกว่า 0';
      }
      final sumSplit = splits.fold(
        0,
        (a, s) => a + (int.tryParse(s.qtyCtrl.text.trim()) ?? 0),
      );
      if (sumSplit > qty) return 'sum splits ($sumSplit) เกิน group qty ($qty)';
    }

    if (tfRsCode == 3) {
      final _effectivePart = (outPartNoMerge?.isNotEmpty == true)
          ? outPartNoMerge
          : defaultPartNo;
      if (_effectivePart == null || _effectivePart.isEmpty)
        return 'กรุณาเลือก Out Part No';
      if (mergeLots.length < 2) return 'ต้องมีอย่างน้อย 2 merge_lots';
      for (final m in mergeLots) {
        if (m.fromLotNo == null || m.fromLotNo!.isEmpty)
          return 'เลือก From Lot ใน merge ให้ครบ';
        final q = int.tryParse(m.qtyCtrl.text.trim());
        if (q == null) return 'qty ใน merge ต้องเป็นตัวเลข';
        if (q <= 0) return 'qty ใน merge ต้องมากกว่า 0';
      }
      final sumMerge = mergeLots.fold(
        0,
        (a, m) => a + (int.tryParse(m.qtyCtrl.text.trim()) ?? 0),
      );
      if (sumMerge != qty) return 'sum merge ($sumMerge) ≠ group qty ($qty)';
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;

    if (tfRsCode == 1) {
      return {
        'tf_rs_code': 1,
        'qty': qty,
        'out_part_no': outPartNo ?? defaultPartNo ?? '',
        if (fromLotNo != null && fromLotNo!.isNotEmpty)
          'from_lot_no': fromLotNo,
        if (colorId != null) 'color_id': colorId,
      };
    }
    if (tfRsCode == 2) {
      return {
        'tf_rs_code': 2,
        'qty': qty,
        'out_part_no': outPartNoGroup ?? defaultPartNo ?? '',
        if (fromLotNo != null && fromLotNo!.isNotEmpty)
          'from_lot_no': fromLotNo,
        'splits': splits
            .map(
              (s) => {
                'out_part_no': s.partNo ?? '',
                'qty': int.tryParse(s.qtyCtrl.text.trim()) ?? 0,
                if (s.colorId != null) 'color_id': s.colorId,
              },
            )
            .toList(),
      };
    }
    // tf=3
    return {
      'tf_rs_code': 3,
      'out_part_no': outPartNoMerge ?? defaultPartNo ?? '',
      if (colorId != null) 'color_id': colorId,
      'merge_lots': mergeLots
          .map(
            (m) => {
              'from_lot_no': m.fromLotNo ?? '',
              'qty': int.tryParse(m.qtyCtrl.text.trim()) ?? 0,
            },
          )
          .toList(),
    };
  }
}

class _SplitEntry {
  String? partNo;
  int? colorId; // STA006 only — per-split color
  final qtyCtrl = TextEditingController();
}

class _MergeLotEntry {
  String? fromLotNo;
  final qtyCtrl = TextEditingController();
}

// ══════════════════════════════════════════════════════════════════
// Group Card
// ══════════════════════════════════════════════════════════════════

class _GroupCard extends StatefulWidget {
  final int index;
  final _GroupEntry entry;
  final List<String> availableLots; // active lots เท่านั้น (tf=1/2)
  final Set<String> selfUsedMergeLots;
  final Set<String> usedByOtherGroups;
  final List<String> ownParkedLotNos; // own-TK parked lots (tf=3 เท่านั้น)
  final List<String>
  crossTkParkedLotNos; // cross-TK parked lots (tf=3 เท่านั้น)
  final List<Map<String, dynamic>> availableParts;
  final List<Map<String, dynamic>> availableColors; // ✅ STA006: color list
  final String? staId; // ✅ ใช้ตรวจว่าเป็น STA006 หรือไม่
  final bool isFirstScan;
  final Map<String, String> crossTkLotMap;
  final int totalGroups;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _GroupCard({
    super.key,
    required this.index,
    required this.entry,
    required this.availableLots,
    required this.selfUsedMergeLots,
    required this.usedByOtherGroups,
    required this.ownParkedLotNos,
    required this.crossTkParkedLotNos,
    required this.availableParts,
    required this.availableColors,
    required this.staId,
    required this.isFirstScan,
    required this.crossTkLotMap,
    required this.totalGroups,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  _GroupEntry get g => widget.entry;

  // ✅ STA006: แสดง color picker
  bool get _isSta006 => (widget.staId ?? '').trim() == 'STA006';

  // ข้อ 1: CO-ID เท่านั้นที่ใช้ parked lots ได้
  // ต้องมี active lots + parked lots รวมกัน >= 2 จึงจะ CO ได้
  bool get _canCoId {
    final totalForCoId =
        widget.availableLots.length +
        widget.ownParkedLotNos.length +
        widget.crossTkParkedLotNos.length;
    return totalForCoId >= 2;
  }

  // lots สำหรับ merge rows (tf=3): active + own-parked + cross-TK parked
  List<String> get _mergeAvailableLots => [
    ...widget.availableLots,
    // ✅ กรอง parked lots ที่ถูกเลือกใน group อื่นแล้วออก
    ...widget.ownParkedLotNos.where(
      (l) => !widget.usedByOtherGroups.contains(l),
    ),
    ...widget.crossTkParkedLotNos.where(
      (l) => !widget.usedByOtherGroups.contains(l),
    ),
  ];

  // ✅ Helper: สร้าง DropdownMenuItem<String> พร้อม cross-TK label — ไม่ overflow
  static DropdownMenuItem<String> _buildLotDropdownItem(
    String lotNo,
    String? sourceTk,
  ) {
    final isCross = sourceTk != null;
    return DropdownMenuItem<String>(
      value: lotNo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isCross)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz, size: 11, color: Colors.orange.shade700),
                const SizedBox(width: 3),
                Text(
                  'Lot พัก จาก $sourceTk',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          Text(
            lotNo,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isCross ? Colors.orange.shade800 : null,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  bool get _singleLot => widget.availableLots.length == 1;

  final _tfLabels = {1: '1 - Master ID', 2: '2 - Split ID', 3: '3 - Co-ID'};
  final _tfColors = {1: Colors.blue, 2: Colors.purple, 3: Colors.teal};

  @override
  void initState() {
    super.initState();
    _autoLockFromLot();
  }

  void _autoLockFromLot() {
    // ✅ ล็อค From Lot อัตโนมัติเฉพาะตอน isFirstScan (ยังไม่เคย transfer)
    //    และมี lot เดียวเท่านั้น — ถ้าผ่านมาแล้วหรือมี parked lots ให้เลือกเองได้
    if ((g.tfRsCode == 1 || g.tfRsCode == 2) &&
        widget.isFirstScan &&
        widget.availableLots.length == 1 &&
        g.fromLotNo == null &&
        widget.availableLots.isNotEmpty) {
      g.fromLotNo = widget.availableLots.first;
    }
  }

  // ✅ Searchable part dropdown ด้วย showSearch
  void _showPartSearch({
    required String label,
    required String? currentValue,
    required ValueChanged<String?> onPicked,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PartSearchSheet(
        label: label,
        parts: widget.availableParts,
        currentValue: currentValue,
        onPicked: onPicked,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _tfColors[g.tfRsCode] ?? Colors.grey;

    if (!_canCoId && g.tfRsCode == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          g.tfRsCode = 1;
          g.outPartNoMerge = null;
          g.mergeLots
            ..clear()
            ..addAll([_MergeLotEntry(), _MergeLotEntry()]);
        });
        widget.onChanged();
      });
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Group ${widget.index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                if (widget.totalGroups > 1)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Condition
            DropdownButtonFormField<int>(
              value: g.tfRsCode,
              decoration: const InputDecoration(
                labelText: 'Condition',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 1, child: Text(_tfLabels[1]!)),
                DropdownMenuItem(value: 2, child: Text(_tfLabels[2]!)),
                DropdownMenuItem(
                  value: 3,
                  enabled: _canCoId,
                  child: Text(
                    _canCoId ? _tfLabels[3]! : '3 - Co-ID (ต้องมี lot ≥ 2)',
                    style: TextStyle(color: _canCoId ? null : Colors.grey),
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                g.tfRsCode = v ?? 1;
                g.fromLotNo = null;
                g.outPartNo = null;
                // ✅ Co-ID: auto-set default ทันที ไม่บังคับให้เลือกใหม่
                g.outPartNoMerge =
                    (v == 3 && (g.defaultPartNo?.isNotEmpty == true))
                    ? g.defaultPartNo
                    : null;
                _autoLockFromLot();
                widget.onChanged();
              }),
            ),
            const SizedBox(height: 12),

            // ── Qty ของ Group นี้ (ทุก tf) ──
            TextField(
              controller: g.qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Qty ของ Group นี้',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => widget.onChanged(),
            ),
            const SizedBox(height: 4),
            const Text(
              'รวมทุก Group ต้องไม่เกิน จำนวน OK',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            // From Lot (tf=1 / tf=2)
            if ((g.tfRsCode == 1 || g.tfRsCode == 2) &&
                widget.availableLots.isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── From Lot ──
                  Expanded(
                    flex: 3,
                    child:
                        widget.isFirstScan && widget.availableLots.length == 1
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lock_outline,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'From Lot (ล็อคอัตโนมัติ)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      Text(
                                        g.fromLotNo ??
                                            widget.availableLots.first,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : DropdownButtonFormField<String>(
                            value: g.fromLotNo,
                            decoration: const InputDecoration(
                              labelText: 'From Lot',
                              border: OutlineInputBorder(),
                            ),
                            isExpanded: true,
                            selectedItemBuilder: (context) =>
                                widget.availableLots.map((l) {
                                  final isCross = widget.crossTkLotMap
                                      .containsKey(l);
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      l,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isCross
                                            ? Colors.orange.shade800
                                            : null,
                                      ),
                                    ),
                                  );
                                }).toList(),
                            itemHeight:
                                widget.crossTkLotMap.keys.any(
                                  (k) => widget.availableLots.contains(k),
                                )
                                ? 56.0
                                : 48.0,
                            items: widget.availableLots
                                .map(
                                  (l) => _buildLotDropdownItem(
                                    l,
                                    widget.crossTkLotMap[l],
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() {
                              g.fromLotNo = v;
                              widget.onChanged();
                            }),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // ── tf=1: [Part No][สี if STA006][Qty] ──
            if (g.tfRsCode == 1) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 2,
                    child: _PartPickerField(
                      label: 'Out Part No',
                      value: g.outPartNo,
                      defaultValue: g.defaultPartNo,
                      parts: widget.availableParts,
                      onPicked: (v) => setState(() {
                        g.outPartNo = v;
                        widget.onChanged();
                      }),
                    ),
                  ),
                  if (_isSta006) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ColorPickerField(
                        label: 'สี',
                        colorId: g.colorId,
                        colors: widget.availableColors,
                        onChanged: (v) => setState(() {
                          g.colorId = v;
                          widget.onChanged();
                        }),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],

            // tf=2: Splits section
            if (g.tfRsCode == 2) ...[
              const Text(
                'Splits:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'ถ้าไม่เพิ่ม Split = qty ทั้งหมดจะพักอัตโนมัติ',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ...List.generate(
                g.splits.length,
                (i) => _SplitRow(
                  index: i,
                  entry: g.splits[i],
                  availableParts: widget.availableParts,
                  availableColors: widget.availableColors,
                  isSta006: _isSta006,
                  defaultPartNo: g.defaultPartNo, // ✅ ส่ง default ลงไป
                  onChanged: widget.onChanged,
                  onRemove: g.splits.length > 1
                      ? () => setState(() {
                          g.splits.removeAt(i);
                          widget.onChanged();
                        })
                      : null,
                  onTapPartSearch: () => _showPartSearch(
                    label: 'Part No (Split ${i + 1})',
                    currentValue: g.splits[i].partNo,
                    onPicked: (v) {
                      setState(() => g.splits[i].partNo = v);
                      widget.onChanged();
                    },
                  ),
                  onColorChanged: (v) => setState(() {
                    g.splits[i].colorId = v;
                    widget.onChanged();
                  }),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  // ✅ split ใหม่ใช้ default part เดิม
                  g.splits.add(_SplitEntry()..partNo = g.defaultPartNo);
                  widget.onChanged();
                }),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('เพิ่ม Split'),
              ),
            ],

            // tf=3: CO-ID
            if (g.tfRsCode == 3) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _PartPickerField(
                      label: 'Out Part No (ผลลัพธ์รวม)',
                      value: g.outPartNoMerge,
                      defaultValue: g.defaultPartNo,
                      parts: widget.availableParts,
                      onPicked: (v) => setState(() {
                        g.outPartNoMerge = v;
                        widget.onChanged();
                      }),
                    ),
                  ),
                  if (_isSta006) const SizedBox(width: 6),
                  if (_isSta006)
                    Expanded(
                      child: _ColorPickerField(
                        label: 'สี',
                        colorId: g.colorId,
                        colors: widget.availableColors,
                        onChanged: (v) => setState(() {
                          g.colorId = v;
                          widget.onChanged();
                        }),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Merge Lots (เลือก lot ที่จะรวม ≥ 2):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...List.generate(g.mergeLots.length, (i) {
                // กัน lot ซ้ำภายใน merge rows: ซ่อน lot ที่ row อื่นเลือกไปแล้ว
                final otherMergePicked = g.mergeLots
                    .asMap()
                    .entries
                    .where(
                      (e) =>
                          e.key != i &&
                          e.value.fromLotNo != null &&
                          e.value.fromLotNo!.isNotEmpty,
                    )
                    .map((e) => e.value.fromLotNo!)
                    .toSet();
                // ข้อ 1: merge rows (tf=3) ใช้ _mergeAvailableLots
                //   = active lots + own-parked + cross-TK parked
                // (cross-group dedup จัดการจาก availableLots ที่กรองมาแล้ว)
                final lotsForRow = _mergeAvailableLots
                    .where((l) => !otherMergePicked.contains(l))
                    .toList();

                return _MergeLotRow(
                  index: i,
                  entry: g.mergeLots[i],
                  availableLots: lotsForRow,
                  crossTkLotMap: widget.crossTkLotMap,
                  onChanged: widget.onChanged,
                  onRemove: g.mergeLots.length > 2
                      ? () => setState(() {
                          g.mergeLots.removeAt(i);
                          widget.onChanged();
                        })
                      : null,
                );
              }),
              TextButton.icon(
                onPressed: () => setState(() {
                  g.mergeLots.add(_MergeLotEntry());
                  widget.onChanged();
                }),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('เพิ่ม Lot ที่จะรวม'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ✅ Shared height constant — ALL three field types use this
// ══════════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════════
// ✅ Shared height — all three field types use this ONE value
// ══════════════════════════════════════════════════════════════════
const double _kFieldH = 48.0;

// ══════════════════════════════════════════════════════════════════
// ✅ _PartPickerField — outlined label floats top-left, fixed height
// ══════════════════════════════════════════════════════════════════
class _PartPickerField extends StatelessWidget {
  final String label;
  final String? value;
  final String? defaultValue;
  final List<Map<String, dynamic>> parts;
  final ValueChanged<String?> onPicked;

  const _PartPickerField({
    required this.label,
    required this.value,
    required this.defaultValue,
    required this.parts,
    required this.onPicked,
  });

  String _displayText() {
    final v = value ?? defaultValue ?? '';
    if (v.isEmpty) return '';
    if (RegExp(r'^\d{6}-').hasMatch(v)) return '';
    final part = parts.firstWhere(
      (p) => p['part_no']?.toString() == v,
      orElse: () => {},
    );
    final pName = part['part_name']?.toString() ?? '';
    return pName.isNotEmpty ? '$v  •  $pName' : v;
  }

  @override
  Widget build(BuildContext context) {
    final effective = value ?? defaultValue;
    final isEmpty =
        effective == null ||
        effective.isEmpty ||
        RegExp(r'^\d{6}-').hasMatch(effective);
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PartSearchSheet(
          label: label,
          parts: parts,
          currentValue: effective,
          onPicked: onPicked,
        ),
      ),
      child: InputDecorator(
        isEmpty: isEmpty,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          suffixIcon: const Icon(Icons.search_rounded, size: 18),
          constraints: const BoxConstraints.tightFor(height: _kFieldH),
        ),
        child: Text(
          _displayText(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ✅ safe int parser
// ══════════════════════════════════════════════════════════════════
int? _safeInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}

// ══════════════════════════════════════════════════════════════════
// ✅ _ColorPickerField — outlined label floats top-left, same height
// ══════════════════════════════════════════════════════════════════
class _ColorPickerField extends StatelessWidget {
  final String label;
  final int? colorId;
  final List<Map<String, dynamic>> colors;
  final ValueChanged<int?> onChanged;

  const _ColorPickerField({
    required this.label,
    required this.colorId,
    required this.colors,
    required this.onChanged,
  });

  String _displayText() {
    if (colorId == null) return 'กรุณาเลือกสีที่ต้องการ';
    final c = colors.firstWhere(
      (c) => _safeInt(c['color_id']) == colorId,
      orElse: () => {},
    );
    if (c.isEmpty) return 'กรุณาเลือกสีที่ต้องการ';
    final no = c['color_no']?.toString() ?? '';
    final name = c['color_name']?.toString() ?? '';
    return name.isNotEmpty ? '$no  •  $name' : no;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ColorSearchSheet(
          label: label,
          colors: colors,
          currentColorId: colorId,
          onPicked: onChanged,
        ),
      ),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: '🎨 $label',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          suffixIcon: const Icon(Icons.palette_outlined, size: 18),
          constraints: const BoxConstraints.tightFor(height: _kFieldH),
        ),
        child: Text(
          _displayText(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: colorId == null ? Colors.grey.shade500 : Colors.black87,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ✅ _QtyField — TextField with same outlined style + same height
// ══════════════════════════════════════════════════════════════════
class _QtyField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String label;

  const _QtyField({
    required this.controller,
    required this.onChanged,
    this.label = 'Qty',
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        constraints: const BoxConstraints.tightFor(height: _kFieldH),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration.collapsed(hintText: ''),
        onChanged: onChanged,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Part Search Bottom Sheet
// ══════════════════════════════════════════════════════════════════
class _PartSearchSheet extends StatefulWidget {
  final String label;
  final List<Map<String, dynamic>> parts;
  final String? currentValue;
  final ValueChanged<String?> onPicked;

  const _PartSearchSheet({
    required this.label,
    required this.parts,
    required this.currentValue,
    required this.onPicked,
  });

  @override
  State<_PartSearchSheet> createState() => _PartSearchSheetState();
}

class _PartSearchSheetState extends State<_PartSearchSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.parts;
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.parts
          : widget.parts.where((p) {
              final pNo = (p['part_no']?.toString() ?? '').toLowerCase();
              final pName = (p['part_name']?.toString() ?? '').toLowerCase();
              return pNo.contains(q) || pName.contains(q);
            }).toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'ค้นหา Part No / Part Name...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'ไม่พบ Part',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      controller: ctrl,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _filtered[i];
                        final pNo = p['part_no']?.toString() ?? '';
                        final pName = p['part_name']?.toString() ?? '';
                        final selected = pNo == widget.currentValue;
                        return ListTile(
                          selected: selected,
                          selectedColor: Colors.orange,
                          selectedTileColor: Colors.orange.shade50,
                          leading: selected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.orange,
                                )
                              : const Icon(
                                  Icons.radio_button_unchecked,
                                  color: Colors.grey,
                                ),
                          title: Text(
                            pNo,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: pName.isNotEmpty
                              ? Text(
                                  pName,
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                          onTap: () {
                            widget.onPicked(pNo);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Split Row
// ══════════════════════════════════════════════════════════════════
class _SplitRow extends StatelessWidget {
  final int index;
  final _SplitEntry entry;
  final List<Map<String, dynamic>> availableParts;
  final List<Map<String, dynamic>> availableColors;
  final bool isSta006;
  final String? defaultPartNo;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final VoidCallback onTapPartSearch;
  final ValueChanged<int?> onColorChanged;

  const _SplitRow({
    required this.index,
    required this.entry,
    required this.availableParts,
    required this.availableColors,
    required this.isSta006,
    required this.defaultPartNo,
    required this.onChanged,
    required this.onTapPartSearch,
    required this.onColorChanged,
    this.onRemove,
  });

  String _partDisplay() {
    final v = entry.partNo ?? defaultPartNo ?? '';
    if (v.isEmpty) return '';
    if (RegExp(r'^\d{6}-').hasMatch(v)) return '';
    final part = availableParts.firstWhere(
      (p) => p['part_no']?.toString() == v,
      orElse: () => {},
    );
    final pName = part['part_name']?.toString() ?? '';
    return pName.isNotEmpty ? '$v  •  $pName' : v;
  }

  @override
  Widget build(BuildContext context) {
    final effective = entry.partNo ?? defaultPartNo;
    final isEmpty =
        effective == null ||
        effective.isEmpty ||
        RegExp(r'^\d{6}-').hasMatch(effective);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: _kFieldH,
            child: Center(
              child: Text(
                '${index + 1}.',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: onTapPartSearch,
              child: InputDecorator(
                isEmpty: isEmpty,
                decoration: const InputDecoration(
                  labelText: 'Part No',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  suffixIcon: Icon(Icons.search_rounded, size: 18),
                  constraints: BoxConstraints.tightFor(height: _kFieldH),
                ),
                child: Text(
                  _partDisplay(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            ),
          ),
          if (isSta006) ...[
            const SizedBox(width: 6),
            Expanded(
              child: _ColorPickerField(
                label: 'สี',
                colorId: entry.colorId,
                colors: availableColors,
                onChanged: onColorChanged,
              ),
            ),
          ],
          const SizedBox(width: 6),
          Expanded(
            child: _QtyField(
              controller: entry.qtyCtrl,
              onChanged: (_) => onChanged(),
            ),
          ),
          if (onRemove != null)
            SizedBox(
              height: _kFieldH,
              child: IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.red,
                  size: 20,
                ),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Color Search Bottom Sheet
// ══════════════════════════════════════════════════════════════════
class _ColorSearchSheet extends StatefulWidget {
  final String label;
  final List<Map<String, dynamic>> colors;
  final int? currentColorId;
  final ValueChanged<int?> onPicked;

  const _ColorSearchSheet({
    required this.label,
    required this.colors,
    required this.currentColorId,
    required this.onPicked,
  });

  @override
  State<_ColorSearchSheet> createState() => _ColorSearchSheetState();
}

class _ColorSearchSheetState extends State<_ColorSearchSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    final active = widget.colors.where((c) {
      final s = c['color_status'];
      if (s == null) return true;
      if (s is bool) return s;
      return int.tryParse(s.toString()) == 1;
    }).toList();
    _filtered = active;
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? active
            : active.where((c) {
                final no = (c['color_no']?.toString() ?? '').toLowerCase();
                final name = (c['color_name']?.toString() ?? '').toLowerCase();
                return no.contains(q) || name.contains(q);
              }).toList();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'ค้นหา Color No / Color Name...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'ไม่พบสี',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      controller: ctrl,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = _filtered[i];
                        final cId = _safeInt(c['color_id']) ?? 0;
                        final cNo = c['color_no']?.toString() ?? '';
                        final cName = c['color_name']?.toString() ?? '';
                        final selected = cId == (widget.currentColorId ?? -1);
                        return ListTile(
                          selected: selected,
                          selectedColor: Colors.orange,
                          selectedTileColor: Colors.orange.shade50,
                          leading: selected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.orange,
                                )
                              : const Icon(
                                  Icons.radio_button_unchecked,
                                  color: Colors.grey,
                                ),
                          title: Text(
                            cNo,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: cName.isNotEmpty
                              ? Text(
                                  cName,
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                          onTap: () {
                            widget.onPicked(_safeInt(c['color_id']));
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Merge Lot Row
// ══════════════════════════════════════════════════════════════════
class _MergeLotRow extends StatelessWidget {
  final int index;
  final _MergeLotEntry entry;
  final List<String> availableLots;
  final Map<String, String> crossTkLotMap;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _MergeLotRow({
    required this.index,
    required this.entry,
    required this.availableLots,
    required this.crossTkLotMap,
    required this.onChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '${index + 1}.',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            value: entry.fromLotNo,
            isExpanded: true,
            menuMaxHeight: 320,
            decoration: const InputDecoration(
              labelText: 'From Lot',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            selectedItemBuilder: (context) => availableLots.map((l) {
              final isCross = crossTkLotMap.containsKey(l);
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isCross ? Colors.orange.shade800 : null,
                  ),
                ),
              );
            }).toList(),
            itemHeight: crossTkLotMap.keys.any((k) => availableLots.contains(k))
                ? 56.0
                : 48.0,
            items: availableLots.map((l) {
              final sourceTk = crossTkLotMap[l];
              return DropdownMenuItem<String>(
                value: l,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (sourceTk != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_horiz,
                            size: 11,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Lot พัก จาก $sourceTk',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    Text(
                      l,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: sourceTk != null ? Colors.orange.shade800 : null,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) {
              entry.fromLotNo = v;
              onChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: TextField(
            controller: entry.qtyCtrl,
            decoration: const InputDecoration(
              labelText: 'Qty',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged(),
          ),
        ),
        if (onRemove != null)
          IconButton(
            icon: const Icon(
              Icons.remove_circle_outline,
              color: Colors.red,
              size: 20,
            ),
            onPressed: onRemove,
          ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
// Info Card
// ══════════════════════════════════════════════════════════════════
class _InfoCard extends StatelessWidget {
  final String tkId;
  final Map<String, dynamic> tkDoc;
  final String? baseLotNo;
  final List<String> currentLots;
  final String? stationId;
  final String? stationName;
  final String? machineId;
  final String? machineName;

  const _InfoCard({
    required this.tkId,
    required this.tkDoc,
    required this.baseLotNo,
    required this.currentLots,
    required this.stationId,
    required this.stationName,
    required this.machineId,
    required this.machineName,
  });

  bool _looksLikeLotNo(String s) => RegExp(r'^\d{6}-').hasMatch(s.trim());

  Map<String, String> _parsePartFromLot(String lotNo) {
    var lot = lotNo.trim();
    final mRun = RegExp(r'-(\d+)$').firstMatch(lot);
    if (mRun != null) lot = lot.substring(0, mRun.start);
    if (lot.length > 7 && lot[6] == '-') lot = lot.substring(7);
    final segs = lot.split('-');
    final idxSpace = segs.indexWhere((x) => x.contains(' '));
    if (idxSpace <= 0) return {'part_no': '', 'part_name': ''};
    return {
      'part_no': segs.take(idxSpace).join('-').trim(),
      'part_name': segs.skip(idxSpace).join('-').trim(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final lotHeader = (baseLotNo ?? '').trim();
    var partNo = (tkDoc['part_no']?.toString() ?? '').trim();
    var partName = (tkDoc['part_name']?.toString() ?? '').trim();

    if (_looksLikeLotNo(partNo)) {
      final p = _parsePartFromLot(partNo);
      partNo = p['part_no'] ?? '';
      partName = p['part_name'] ?? '';
    }
    if (partName.isEmpty && _looksLikeLotNo(lotHeader)) {
      final p = _parsePartFromLot(lotHeader);
      partNo = partNo.isNotEmpty ? partNo : (p['part_no'] ?? '');
      partName = p['part_name'] ?? '';
    }

    final staId = (stationId?.trim().isNotEmpty ?? false)
        ? stationId!.trim()
        : (tkDoc['op_sta_id']?.toString() ?? '-').trim();
    final staName = (stationName?.trim().isNotEmpty ?? false)
        ? stationName!.trim()
        : (tkDoc['op_sta_name']?.toString() ?? '-').trim();
    final mcId = (machineId?.trim().isNotEmpty ?? false)
        ? machineId!.trim()
        : (tkDoc['MC_id']?.toString() ?? '-').trim();
    final mcName = (machineName?.trim().isNotEmpty ?? false)
        ? machineName!.trim()
        : (tkDoc['MC_name']?.toString() ?? '-').trim();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tkId,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Text('Part No: ${partNo.isEmpty ? '-' : partNo}'),
            Text('Part Name: ${partName.isEmpty ? '-' : partName}'),
            Text('Lot No: ${lotHeader.isEmpty ? '-' : lotHeader}'),
            Text('Station: $staId ($staName)'),
            Text('Machine: $mcId ($mcName)'),
            if (currentLots.isNotEmpty) ...[
              const Divider(height: 16),
              const Text(
                'Lots (current):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...currentLots.map(
                (lot) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.fiber_manual_record,
                        size: 8,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lot,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
