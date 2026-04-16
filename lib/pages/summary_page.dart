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

  // 🎨 คืนค่าสี bg / border / text ตาม condition label
  ({Color bg, Color border, Color text}) _tfColor(String tf) {
    switch (tf) {
      case 'Master':
        return (
          bg: Colors.blue.shade50,
          border: Colors.blue.shade200,
          text: Colors.blue.shade800,
        );
      case 'Split':
        return (
          bg: Colors.purple.shade50,
          border: Colors.purple.shade200,
          text: Colors.purple.shade800,
        );
      case 'Co-ID':
        return (
          bg: Colors.green.shade50,
          border: Colors.green.shade200,
          text: Colors.green.shade800,
        );
      default:
        return (
          bg: Colors.grey.shade100,
          border: Colors.grey.shade300,
          text: Colors.grey.shade700,
        );
    }
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
        final rawMsg = body['message']?.toString() ?? 'เกิดข้อผิดพลาด';
        final displayMsg = rawMsg
            .replaceAll('tk_id', 'Tracking No.')
            .replaceAll('not found', 'ไม่มีอยู่ในระบบ')
            .replaceAll('Not found', 'ไม่มีอยู่ในระบบ');
        CoolerAlert.show(
          context,
          title: 'โหลด Summary ไม่สำเร็จ',
          message: displayMsg,
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
    final s = code?.toString().trim() ?? '';
    if (s == 'Master-ID' || s == 'Master') return 'Master';
    if (s == 'Split-ID' || s == 'Split') return 'Split';
    if (s == 'Co-ID') return 'Co-ID';
    final c = int.tryParse(s) ?? 0;
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
  /// รองรับทั้ง stations_history (backend ใหม่) และ flat scans (เก่า)
  List<Map<String, dynamic>> _scans() {
    final sh = _data?['stations_history'];
    if (sh is List && sh.isNotEmpty) {
      final result = <Map<String, dynamic>>[];
      for (final sta in sh) {
        final staId = sta['op_sta_id']?.toString() ?? '';
        final staName = sta['op_sta_name']?.toString() ?? '';
        final s = sta['scans'];
        if (s is List) {
          for (final raw in s) {
            final scan = Map<String, dynamic>.from(raw as Map);
            // inject station info จาก parent ถ้า scan ยังไม่มี
            scan['op_sta_id'] ??= staId;
            scan['op_sta_name'] ??= staName;
            // inject tf_rs_name เป็น tf_rs_code fallback ให้ _tfLabel ทำงานได้
            if (scan['tf_rs_code'] == null && scan['tf_rs_name'] != null) {
              scan['tf_rs_code'] = scan['tf_rs_name'];
            }
            result.add(scan);
          }
        }
      }
      return result;
    }
    final s = _data?['scans'];
    if (s is List)
      return s.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  /// ดึง list transfers จาก payload
  /// รองรับทั้ง nested ใน scans (backend ใหม่) และ flat transfers (เก่า)
  List<Map<String, dynamic>> _transfers() {
    final sh = _data?['stations_history'];
    if (sh is List && sh.isNotEmpty) {
      final result = <Map<String, dynamic>>[];
      for (final sta in sh) {
        final scans = sta['scans'];
        if (scans is List) {
          for (final scan in scans) {
            final t = scan['transfers'];
            if (t is List)
              result.addAll(t.map((e) => Map<String, dynamic>.from(e as Map)));
          }
        }
      }
      if (result.isNotEmpty) return result;
    }
    final t = _data?['transfers'];
    if (t is List)
      return t.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
    final transfers = _transfers();

    // track first-seen transfer_ts for each lot (as to_lot_no = when it was born)
    final firstSeenTs = <String, String>{};
    for (final t in transfers) {
      final ts = t['transfer_ts']?.toString() ?? '';
      final tl = (t['to_lot_no']?.toString() ?? '').trim();
      if (tl.isNotEmpty && ts.isNotEmpty) {
        if (!firstSeenTs.containsKey(tl)) firstSeenTs[tl] = ts;
      }
    }

    // also include from_lot_no that never appear as to_lot (original lot from TKDoc)
    final originalLot =
        (_data?['tk']?['lot_no']?.toString() ??
                _data?['current']?['lot_no']?.toString() ??
                '')
            .trim();
    if (originalLot.isNotEmpty && !firstSeenTs.containsKey(originalLot)) {
      firstSeenTs[originalLot] = '';
    }

    final lots = firstSeenTs.keys.toList();
    lots.sort((a, b) {
      final ta = firstSeenTs[a] ?? '';
      final tb = firstSeenTs[b] ?? '';
      if (ta.isEmpty && tb.isEmpty) return a.compareTo(b);
      if (ta.isEmpty) return -1; // original lot (no ts) goes first
      if (tb.isEmpty) return 1;
      return ta.compareTo(tb);
    });
    return lots;
  }

  void _openScanDetail(Map<String, dynamic> scan) {
    final opScId = scan['op_sc_id']?.toString() ?? '';
    final trs = _transfersByOpSc(opScId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
        maxWidth: 560,
      ),
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
                  _kv('Condition', _tfLabel(scan['tf_rs_code'])),
                  _kv(
                    'OK / NG',
                    '${_fmtNum(scan['op_sc_good_qty'])} / ${_fmtNum(scan['op_sc_scrap_qty'])}',
                  ),
                  _kv('Lot No', scan['lot_no']?.toString() ?? '-'),
                  _kv('Start', _fmtTs(scan['op_sc_ts']?.toString())),
                  _kv('Finish', _fmtTs(scan['op_sc_finish_ts']?.toString())),

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
                    ...() {
                      // ✅ build transfer cards พร้อม separator แดงก่อน lot "ไม่ได้ใช้" ตัวแรก
                      final result = <Widget>[];
                      bool separatorInserted = false;

                      for (final t in trs) {
                        final tf = _tfLabel(t['tf_rs_code']);
                        final fromLot = (t['from_lot_no']?.toString() ?? '-')
                            .trim();
                        final toLot = (t['to_lot_no']?.toString() ?? '-')
                            .trim();
                        final qty = t['transfer_qty']?.toString() ?? '0';
                        final ts = _fmtTs(t['transfer_ts']?.toString());
                        final fromTk = t['from_tk_id']?.toString() ?? '';
                        final toTk = t['to_tk_id']?.toString() ?? '';

                        // ✅ color info (STA006)
                        final colorId = t['color_id'];
                        final colorNo = t['color_no']?.toString() ?? '';
                        final colorName = t['color_name']?.toString() ?? '';
                        final hasColor = colorId != null && colorNo.isNotEmpty;

                        // lot_parked_status=1 → lot นี้ถูก mark พักไว้
                        final _ps = t['lot_parked_status'];
                        final isParked = _toInt01(_ps) == 1;

                        // ✅ เช็ค station
                        final scanStaId = scan['op_sta_id']?.toString() ?? '';
                        final tStaId = t['op_sta_id']?.toString() ?? '';
                        final isParkedHere = isParked && tStaId == scanStaId;

                        // from_tk ≠ to_tk → cross-TK
                        final isCrossTk =
                            fromTk.isNotEmpty &&
                            toTk.isNotEmpty &&
                            fromTk != toTk;

                        // ✅ isAutoParked: lot ไม่ถูกเลือกใช้เลยใน scan นี้
                        //
                        // กรณี 1 — split ไม่ครบ: backend gen lot ใหม่ → from_lot ≠ to_lot เสมอ
                        //           (e.g. from=lot1, to=lot4_new) → isAutoParked=false → ORANGE
                        //
                        // กรณี 2 — lot ไม่ถูกเลือก (auto-park): backend INSERT row ใหม่
                        //           from_lot == to_lot (same lot) → isAutoParked=true → RED
                        //
                        // ✅ isSameLot: from_lot == to_lot → ต้องเป็น case 2 เสมอ (ไม่ว่า backend เก่าหรือใหม่)
                        //    รองรับทั้ง backend เก่า (ที่ UPDATE row เดิมผิด) และ backend ใหม่ (INSERT-only)
                        final isSameLot =
                            fromLot.isNotEmpty && fromLot == toLot;

                        final usedAsSource = trs.any(
                          (other) =>
                              (other['from_lot_no']?.toString() ?? '') ==
                                  toLot &&
                              other != t &&
                              _toInt01(other['lot_parked_status']) == 0,
                        );
                        final fromLotActivelyUsed = trs.any(
                          (other) =>
                              (other['from_lot_no']?.toString() ?? '') ==
                                  fromLot &&
                              other != t &&
                              _toInt01(other['lot_parked_status']) == 0,
                        );
                        final isAutoParked =
                            isParked &&
                            !isCrossTk &&
                            // from==to → case 2 auto-park แน่นอน (bypass usedAsSource check)
                            // from≠to → ใช้ usedAsSource / fromLotActivelyUsed ตามปกติ
                            (isSameLot ||
                                (!usedAsSource && !fromLotActivelyUsed));

                        // ✅ แทรกเส้นแดงคั่นก่อน lot ไม่ได้ใช้ตัวแรก
                        if (isAutoParked && !separatorInserted) {
                          separatorInserted = true;
                          result.add(
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      thickness: 1.5,
                                      color: Colors.red.shade200,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          size: 12,
                                          color: Colors.red.shade400,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Lot ไม่ได้ใช้ใน scan นี้ ต้องนำไป Co-ID ก่อน',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red.shade400,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      thickness: 1.5,
                                      color: Colors.red.shade200,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final card = Card(
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
                                    // ✅ isAutoParked → badge แดง "ไม่ได้ใช้" แทน Condition chip
                                    if (isAutoParked)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.red.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          '🔴 ไม่ได้ใช้',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                      )
                                    else
                                      // 🎨 badge สีตาม condition: Master=ฟ้า, Split=ม่วง, Co-ID=เขียว
                                      Builder(
                                        builder: (_) {
                                          final c = _tfColor(tf);
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.bg,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: c.border,
                                              ),
                                            ),
                                            child: Text(
                                              tf,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: c.text,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    const SizedBox(width: 6),
                                    // badge ส้ม: lot พักปกติ (ไม่ใช่ auto-park)
                                    if (isParkedHere &&
                                        !isCrossTk &&
                                        !isAutoParked)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          fromTk.isNotEmpty
                                              ? '🔵 Lot พักของ $fromTk'
                                              : '🔵 Lot พัก',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.orange.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    // badge เขียว: ดึง lot พักจาก TK อื่นมาใช้
                                    if (isCrossTk)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.green.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          '✅ นำ lot พักมาใช้จาก $fromTk',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    const Spacer(),
                                    Text(
                                      'Qty: ${_fmtNum(t['transfer_qty'])}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _kvSmall('From', fromLot),
                                _kvSmall('To', toLot),
                                // ✅ แสดงสีเฉพาะ row ที่มี color_id (STA006)
                                if (hasColor)
                                  _kvSmall(
                                    '🎨 สี',
                                    colorName.isNotEmpty
                                        ? '$colorNo  •  $colorName'
                                        : colorNo,
                                  ),
                                _kvSmall('Time', ts),
                              ],
                            ),
                          ),
                        );
                        result.add(card);
                      }
                      return result;
                    }(),
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

  String _fmtNum(dynamic v) {
    if (v == null) return '0';
    final n =
        int.tryParse(v.toString()) ??
        double.tryParse(v.toString())?.toInt() ??
        0;
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  String _fmtTs(String? iso) {
    if (iso == null || iso == '-') return '-';
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

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final current = (data?['current'] is Map)
        ? Map<String, dynamic>.from(data!['current'] as Map)
        : <String, dynamic>{};
    final scans = _scans();
    final lotsAll = _allLotsFromPayload();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
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
                          _kv(
                            'Lot No',
                            // ✅ ใช้ base.lot_no จาก backend โดยตรง (lot แรกของเอกสาร)
                            // fallback → _motherLotFromPayload() กรณี finishResult ยังไม่มี base
                            (_data?['base']?['lot_no']?.toString() ?? '')
                                    .isNotEmpty
                                ? _data!['base']['lot_no'].toString()
                                : _motherLotFromPayload(),
                          ),
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
                                    'SC: $opScId\nMC: $mc | OK: ${_fmtNum(good)} | NG: ${_fmtNum(scrap)} | $type',
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
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 180),
                              child: Scrollbar(
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: _parkedLots().map((pl) {
                                      final lotNo =
                                          (pl['parked_lot_no'] ?? pl['lot_no'])
                                              ?.toString() ??
                                          '-';
                                      final qty =
                                          (pl['parked_qty'] ?? pl['qty'])
                                              ?.toString() ??
                                          '-';
                                      final sta =
                                          (pl['op_sta_id'] ??
                                                  pl['parked_at_sta'])
                                              ?.toString() ??
                                          '-';
                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    'Station: $sta  •  Qty: ${_fmtNum(pl['parked_qty'] ?? pl['qty'])}',
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
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'ประวัติ Lots ทั้งหมดใน ${widget.tkId}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (lotsAll.isEmpty)
                            const Text(
                              'ยังไม่มี Lot',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            )
                          else
                            ...lotsAll.asMap().entries.map((e) {
                              final idx = e.key;
                              final lot = e.value;
                              final isLatest = idx == lotsAll.length - 1;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      child: Text(
                                        '${idx + 1}.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isLatest
                                              ? Colors.blue.shade700
                                              : Colors.grey,
                                          fontWeight: isLatest
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        lot,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isLatest
                                              ? Colors.blue.shade700
                                              : Colors.black54,
                                          fontWeight: isLatest
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (isLatest)
                                      Container(
                                        margin: const EdgeInsets.only(
                                          left: 6,
                                          top: 1,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue.shade200,
                                          ),
                                        ),
                                        child: const Text(
                                          'ล่าสุด',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.blue,
                                          ),
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
                ],
              ),
            ),
    );
  }
}
