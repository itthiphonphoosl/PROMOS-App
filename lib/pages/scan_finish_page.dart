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
    return all.first; // ✅ base = run_no เล็กสุด
  }

  Future<void> _loadCurrentLotsFromSummary() async {
    // base lot จาก list ที่ส่งเข้ามา
    _baseLotNo ??= _pickBaseLotFromAllLots();

    try {
      final res = await ApiService.getSummaryByTkId(widget.tkId);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        final transfers = (body['transfers'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final fromSet = <String>{};
        final toSet = <String>{};

        for (final t in transfers) {
          final fromLot = (t['from_lot_no']?.toString() ?? '').trim();
          final toLot = (t['to_lot_no']?.toString() ?? '').trim();
          if (fromLot.isNotEmpty) fromSet.add(fromLot);
          if (toLot.isNotEmpty) toSet.add(toLot);
        }

        // ✅ leaf lots = toSet - fromSet
        final leaf = toSet.difference(fromSet).toList();
        leaf.sort((a, b) => _runSuffix(a).compareTo(_runSuffix(b)));

        if (mounted) {
          setState(() {
            _currentLots = leaf.isNotEmpty
                ? leaf
                : (_baseLotNo != null ? [_baseLotNo!] : []);
            _loadingLots = false;
          });
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _currentLots = _baseLotNo != null ? [_baseLotNo!] : [];
        _loadingLots = false;
      });
    }
  }

  List<Map<String, dynamic>> _parts = [];
  bool _loadingParts = true;

  String _familyPrefix(String partNo) {
    final s = partNo.trim();
    if (s.isEmpty) return '';
    final seg = s.split('-');
    // ex: 382-B42-002D-K0B  => 382-B42-002D
    if (seg.length >= 3) return '${seg[0]}-${seg[1]}-${seg[2]}';
    return s;
  }

  int _goodQty() => int.tryParse(_goodCtrl.text.trim()) ?? 0;

  int _sumGroupQty() =>
      _groups.fold(0, (a, g) => a + (int.tryParse(g.qtyCtrl.text.trim()) ?? 0));

  int _remainingGood() => _goodQty() - _sumGroupQty();

  @override
  void initState() {
    super.initState();
    _loadParts();
    _loadCurrentLotsFromSummary(); // ✅ เพิ่ม

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _ensureOneGroup();
      });
    });
  }

  bool get _isSimpleFlow {
    final lots = _currentLots.where((s) => s.trim().isNotEmpty).toList();
    if (lots.isEmpty) return true;
    return lots.length <= 1;
  }

  void _ensureOneGroup() {
    if (_groups.isEmpty) {
      _groups.add(_GroupEntry());
    }
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

  @override
  void dispose() {
    _goodCtrl.dispose();
    _scrapCtrl.dispose();
    super.dispose();
  }

  void _addGroup() {
    final remaining = _remainingGood();
    if (remaining <= 0) return;

    final entry = _GroupEntry();
    entry.qtyCtrl.text = remaining.toString();
    setState(() => _groups.add(entry));
  }

  void _removeGroup(int i) => setState(() => _groups.removeAt(i));

  Future<void> _finish() async {
    final goodRaw = int.tryParse(_goodCtrl.text.trim());
    final scrapRaw = int.tryParse(_scrapCtrl.text.trim());

    if (goodRaw == null || scrapRaw == null) {
      CoolerAlert.show(
        context,
        message: 'กรุณากรอก Good Qty และ Scrap Qty เป็นตัวเลข',
        type: CoolerAlertType.warning,
      );
      return;
    }

    final good = goodRaw.abs();
    final scrap = scrapRaw.abs();

    // (แนะนำให้ตรงหลังบ้าน) ถ้าทั้งคู่เป็น 0 ไม่ควรส่ง finish
    if (good == 0 && scrap == 0) {
      CoolerAlert.show(
        context,
        message: 'Good และ Scrap ห้ามเป็น 0 พร้อมกัน',
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

    // ── validate: รวม qty ทุก group ต้องเท่ากับ good_qty ──────────
    final sumGroupQty = _groups.fold(
      0,
      (a, g) => a + ((int.tryParse(g.qtyCtrl.text.trim()) ?? 0).abs()),
    );
    if (sumGroupQty != good) {
      CoolerAlert.show(
        context,
        message:
            'รวม qty ทุก Group ($sumGroupQty) ≠ good_qty ($good)\nกรุณาตรวจสอบ',
        type: CoolerAlertType.warning,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    // ── validate รายละเอียด group ──────────────────────────────────
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

    setState(() => _finishing = true);
    try {
      final res = await ApiService.finishScan(
        opScId: widget.opScId,
        goodQty: good,
        scrapQty: scrap,
        groups: _groups.map((g) => g.toJson()).toList(),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200) {
        CoolerAlert.show(
          context,
          title: 'Finish สำเร็จ!',
          message:
              'tk_status: ${body['tk_status']} | groups: ${body['created_groups_count']}',
          type: CoolerAlertType.success,
          duration: const Duration(seconds: 3),
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
          duration: const Duration(seconds: 4),
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
  Widget build(BuildContext context) {
    final lots = _currentLots; // ✅ เอาไปทำต่อได้จริง (leaf lots)

    final canAddGroup = !_isSimpleFlow && _remainingGood() > 0;
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
            // ── TK Info ────────────────────────────────────────────
            _InfoCard(
              tkId: widget.tkId,
              tkDoc: widget.tkDoc,
              baseLotNo: _baseLotNo,
              currentLots: lots,
            ),
            const SizedBox(height: 16),

            // ── Qty Input ──────────────────────────────────────────
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
                              labelText: 'Good Qty ✅',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) {
                              setState(() {
                                _ensureOneGroup();
                                if (_groups.length == 1) {
                                  _groups[0].qtyCtrl.text = _goodQty()
                                      .abs()
                                      .toString(); // ✅ realtime ตาม good
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
                              labelText: 'Scrap Qty ❌',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    // ── แสดง total qty summary แบบ real-time ──────
                    Builder(
                      builder: (ctx) {
                        final g = (int.tryParse(_goodCtrl.text.trim()) ?? 0)
                            .abs();
                        final s = (int.tryParse(_scrapCtrl.text.trim()) ?? 0)
                            .abs();
                        final total = g + s;

                        final sumGroups = _groups.fold(
                          0,
                          (a, x) =>
                              a +
                              ((int.tryParse(x.qtyCtrl.text.trim()) ?? 0)
                                  .abs()),
                        );

                        final remaining = g - sumGroups;

                        // ไม่โชว์ถ้ายังไม่มีอะไรกรอกเลย
                        if (total <= 0 && sumGroups <= 0)
                          return const SizedBox.shrink();

                        final warn =
                            remaining != 0; // ✅ ต้องเหลือ 0 ถึงจะตรงกับหลังบ้าน

                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: warn
                                  ? Colors.orange.shade50
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: warn
                                    ? Colors.orange.shade200
                                    : Colors.green.shade200,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total qty (good+scrap) = $total',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Sum Group qty = $sumGroups  (ต้องเท่ากับ Good Qty = $g)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Remaining (Good - SumGroups) = $remaining',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: warn
                                        ? Colors.orange.shade800
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

            // ── Loading parts hint ─────────────────────────────────
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

            // ── Groups ─────────────────────────────────────────────
            ...List.generate(
              _groups.length,
              (i) => _GroupCard(
                index: i,
                entry: _groups[i],
                availableLots: lots,
                availableParts: _parts,
                onChanged: () => setState(() {}),
                onRemove: () => _removeGroup(i),
              ),
            ),

            OutlinedButton.icon(
              onPressed: canAddGroup
                  ? _addGroup
                  : null, // ✅ ปิดเมื่อ remaining <= 0
              icon: const Icon(Icons.add),
              label: Text(
                canAddGroup ? 'เพิ่ม Group' : 'เพิ่ม Group (ครบแล้ว)',
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange),
                foregroundColor: Colors.orange,
              ),
            ),
            const SizedBox(height: 24),

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
                        height: 20,
                        width: 20,
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
// Models
// ══════════════════════════════════════════════════════════════════

class _GroupEntry {
  int tfRsCode = 1;
  final qtyCtrl = TextEditingController();

  // tf=1 & tf=2 shared
  String? fromLotNo;

  // tf=1
  String? outPartNo;

  // tf=2
  final List<_SplitEntry> splits = [_SplitEntry(), _SplitEntry()];

  // tf=3
  String? outPartNoMerge;
  final List<_MergeLotEntry> mergeLots = [_MergeLotEntry(), _MergeLotEntry()];

  String? validate() {
    final qty = int.tryParse(qtyCtrl.text.trim());
    if (qty == null || qty <= 0) return 'qty ต้องมากกว่า 0';

    if (tfRsCode == 1) {
      if (outPartNo == null || outPartNo!.isEmpty)
        return 'กรุณาเลือก Out Part No';
    }

    if (tfRsCode == 2) {
      if (splits.length < 2) return 'ต้องมีอย่างน้อย 2 splits';
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
      if (sumSplit != qty) return 'sum splits ($sumSplit) ≠ group qty ($qty)';
    }

    if (tfRsCode == 3) {
      if (outPartNoMerge == null || outPartNoMerge!.isEmpty)
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
        'out_part_no': outPartNo ?? '',
        if (fromLotNo != null && fromLotNo!.isNotEmpty)
          'from_lot_no': fromLotNo,
      };
    }

    if (tfRsCode == 2) {
      return {
        'tf_rs_code': 2,
        'qty': qty,
        if (fromLotNo != null && fromLotNo!.isNotEmpty)
          'from_lot_no': fromLotNo,
        'splits': splits
            .map(
              (s) => {
                'out_part_no': s.partNo ?? '',
                'qty': int.tryParse(s.qtyCtrl.text.trim()) ?? 0,
              },
            )
            .toList(),
      };
    }

    // tf=3
    return {
      'tf_rs_code': 3,
      'qty': qty,
      'out_part_no': outPartNoMerge ?? '',
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
  final qtyCtrl = TextEditingController();
}

class _MergeLotEntry {
  String? fromLotNo;
  final qtyCtrl = TextEditingController();
}

class _GroupCard extends StatefulWidget {
  final int index;
  final _GroupEntry entry;
  final List<String> availableLots;
  final List<Map<String, dynamic>> availableParts;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _GroupCard({
    required this.index,
    required this.entry,
    required this.availableLots,
    required this.availableParts,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  _GroupEntry get g => widget.entry;
  bool get _canCoId => widget.availableLots.length >= 2;
  final _tfLabels = {1: '1 - Master ID', 2: '2 - Split ID', 3: '3 - Co-ID'};
  final _tfColors = {1: Colors.blue, 2: Colors.purple, 3: Colors.teal};

  bool get _singleLot => widget.availableLots.length == 1;

  @override
  void initState() {
    super.initState();
    _autoLockFromLot();
  }

  void _autoLockFromLot() {
    if ((g.tfRsCode == 1 || g.tfRsCode == 2) &&
        _singleLot &&
        g.fromLotNo == null &&
        widget.availableLots.isNotEmpty) {
      g.fromLotNo = widget.availableLots.first;
    }
  }

  Widget _partDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final parts = widget.availableParts;

    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      menuMaxHeight: 320,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
      hint: const Text('เลือก Part No'),

      // ✅ ตอนเลือกแล้วโชว์บรรทัดเดียว กัน overflow
      selectedItemBuilder: (context) {
        return parts.map((p) {
          final pNo = p['part_no']?.toString() ?? '';
          final pName = p['part_name']?.toString() ?? '';
          final text = pName.isEmpty ? pNo : '$pNo • $pName';
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
        }).toList();
      },

      // ✅ เมนู dropdown ยังโชว์ 2 บรรทัดได้
      items: parts.map((p) {
        final pNo = p['part_no']?.toString() ?? '';
        final pName = p['part_name']?.toString() ?? '';
        return DropdownMenuItem<String>(
          value: pNo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pNo,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              if (pName.isNotEmpty)
                Text(
                  pName,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        );
      }).toList(),

      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _tfColors[g.tfRsCode] ?? Colors.grey;

    // ✅ ถ้า lot < 2 แล้วค่าดันเป็น Co-ID อยู่ ให้เด้งกลับเป็น Master อัตโนมัติ
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
            // ── Header ─────────────────────────────────────────────
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
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              value: g.tfRsCode,
              decoration: const InputDecoration(
                labelText: 'Transfer Type',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 1, child: Text(_tfLabels[1]!)),
                DropdownMenuItem(value: 2, child: Text(_tfLabels[2]!)),
                DropdownMenuItem(
                  value: 3,
                  enabled: _canCoId, // ✅ lot < 2 => ปิด Co-ID
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
                g.outPartNoMerge = null;
                _autoLockFromLot();
                widget.onChanged();
              }),
            ),
            const SizedBox(height: 12),

            // ── Qty (auto-filled = good + scrap) ──────────────────
            TextField(
              controller: g.qtyCtrl,
              decoration: const InputDecoration(
                labelText: 'Qty ของ Group นี้',
                border: OutlineInputBorder(),
                helperText: 'รวมทุก Group ต้องเท่ากับ Good Qty (ไม่นับ scrap)',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => widget.onChanged(),
            ),
            const SizedBox(height: 12),

            // ── From Lot (tf=1 & tf=2) ─────────────────────────────
            if ((g.tfRsCode == 1 || g.tfRsCode == 2) &&
                widget.availableLots.isNotEmpty) ...[
              if (_singleLot)
                Container(
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'From Lot (ล็อคอัตโนมัติ)',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue,
                              ),
                            ),
                            Text(
                              g.fromLotNo ?? widget.availableLots.first,
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
              else
                DropdownButtonFormField<String>(
                  value: g.fromLotNo,
                  decoration: const InputDecoration(
                    labelText: 'From Lot',
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items: widget.availableLots
                      .map(
                        (l) => DropdownMenuItem(
                          value: l,
                          child: Text(l, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    g.fromLotNo = v;
                    widget.onChanged();
                  }),
                ),
              const SizedBox(height: 12),
            ],
            // ── tf=1: Out Part No dropdown ─────────────────────────
            if (g.tfRsCode == 1)
              _partDropdown(
                label: 'Out Part No',
                value: g.outPartNo,
                onChanged: (v) => setState(() {
                  g.outPartNo = v;
                  widget.onChanged();
                }),
              ),

            // ── tf=2: Splits ───────────────────────────────────────
            if (g.tfRsCode == 2) ...[
              const Text(
                'Splits:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...List.generate(
                g.splits.length,
                (i) => _SplitRow(
                  index: i,
                  entry: g.splits[i],
                  availableParts: widget.availableParts,
                  onChanged: widget.onChanged,
                  onRemove: g.splits.length > 2
                      ? () => setState(() {
                          g.splits.removeAt(i);
                          widget.onChanged();
                        })
                      : null,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  g.splits.add(_SplitEntry());
                  widget.onChanged();
                }),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('เพิ่ม Split'),
              ),
            ],

            // ── tf=3: Co-ID Merge ──────────────────────────────────
            if (g.tfRsCode == 3) ...[
              _partDropdown(
                label: 'Out Part No (ผลลัพธ์รวม)',
                value: g.outPartNoMerge,
                onChanged: (v) => setState(() {
                  g.outPartNoMerge = v;
                  widget.onChanged();
                }),
              ),
              const SizedBox(height: 12),
              const Text(
                'Merge Lots (เลือก lot ที่จะรวม ≥ 2):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...List.generate(
                g.mergeLots.length,
                (i) => _MergeLotRow(
                  index: i,
                  entry: g.mergeLots[i],
                  availableLots: widget.availableLots,
                  onChanged: widget.onChanged,
                  onRemove: g.mergeLots.length > 2
                      ? () => setState(() {
                          g.mergeLots.removeAt(i);
                          widget.onChanged();
                        })
                      : null,
                ),
              ),
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

class _SplitRow extends StatelessWidget {
  final int index;
  final _SplitEntry entry;
  final List<Map<String, dynamic>> availableParts;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _SplitRow({
    required this.index,
    required this.entry,
    required this.availableParts,
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
          flex: 3,
          child: DropdownButtonFormField<String>(
            value: entry.partNo,
            decoration: const InputDecoration(
              labelText: 'Part No',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            hint: const Text('เลือก', style: TextStyle(fontSize: 12)),
            isExpanded: true,
            menuMaxHeight: 280,
            items: availableParts.map((p) {
              final pNo = p['part_no']?.toString() ?? '';
              final pName = p['part_name']?.toString() ?? '';
              return DropdownMenuItem<String>(
                value: pNo,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pNo,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (pName.isNotEmpty)
                      Text(
                        pName,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) {
              entry.partNo = v;
              onChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: entry.qtyCtrl,
            decoration: const InputDecoration(
              labelText: 'Qty',
              border: OutlineInputBorder(),
              isDense: true,
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
// Merge Lot Row
// ══════════════════════════════════════════════════════════════════

class _MergeLotRow extends StatelessWidget {
  final int index;
  final _MergeLotEntry entry;
  final List<String> availableLots;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _MergeLotRow({
    required this.index,
    required this.entry,
    required this.availableLots,
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
          flex: 3,
          child: DropdownButtonFormField<String>(
            value: entry.fromLotNo,
            isExpanded: true,
            menuMaxHeight: 280,
            decoration: const InputDecoration(
              labelText: 'From Lot',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: availableLots
                .map(
                  (l) => DropdownMenuItem(
                    value: l,
                    child: Text(
                      l,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              entry.fromLotNo = v;
              onChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: entry.qtyCtrl,
            decoration: const InputDecoration(
              labelText: 'Qty',
              border: OutlineInputBorder(),
              isDense: true,
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

class _InfoCard extends StatelessWidget {
  final String tkId;
  final Map<String, dynamic> tkDoc;
  final String? baseLotNo;
  final List<String> currentLots;

  const _InfoCard({
    required this.tkId,
    required this.tkDoc,
    required this.baseLotNo,
    required this.currentLots,
  });

  bool _looksLikeLotNo(String s) => RegExp(r'^\d{6}-').hasMatch(s.trim());

  Map<String, String> _parsePartFromLot(String lotNo) {
    var lot = lotNo.trim();

    // ตัด -RUNNO ท้ายสุด เช่น -00000000000141
    final mRun = RegExp(r'-(\d+)$').firstMatch(lot);
    if (mRun != null) {
      lot = lot.substring(0, mRun.start);
    }

    // ตัด prefix วันที่ YYMMDD-
    if (lot.length > 7 && lot[6] == '-') {
      lot = lot.substring(7);
    }

    final segs = lot.split('-');
    final idxSpace = segs.indexWhere((x) => x.contains(' '));

    // ถ้าไม่เจอ space เลย แปลว่า parse ไม่ได้ชัวร์
    if (idxSpace <= 0) {
      return {'part_no': '', 'part_name': ''};
    }

    final partNo = segs.take(idxSpace).join('-').trim();
    final partName = segs.skip(idxSpace).join('-').trim();
    return {'part_no': partNo, 'part_name': partName};
  }

  @override
  Widget build(BuildContext context) {
    // ✅ current lot = เอา lot ที่ทำต่อได้จริง (leaf) ตัวแรก
    final firstLot = (baseLotNo ?? tkDoc['lot_no']?.toString() ?? '').trim();

    // ✅ current lot = เอา lot ที่ทำต่อได้จริง (leaf) ตัวแรก (ไว้โชว์ใน list ด้านล่าง)
    final currentLot = currentLots.isNotEmpty
        ? currentLots.first.trim()
        : (tkDoc['lot_no']?.toString() ?? baseLotNo ?? '').trim();

    // ค่าจาก tkDoc
    var partNo = (tkDoc['part_no']?.toString() ?? '').trim();
    var partName = (tkDoc['part_name']?.toString() ?? '').trim();

    // ✅ ถ้า partNo ดันเป็น lot_no (ขึ้นต้นด้วย YYMMDD-) ให้แปลงกลับเป็น part_no/part_name
    if (_looksLikeLotNo(partNo)) {
      final parsed = _parsePartFromLot(partNo);
      partNo = parsed['part_no'] ?? '';
      partName = parsed['part_name'] ?? '';
    }

    // ✅ ถ้า partName ยังว่าง แต่มี currentLot → ลอง parse จาก currentLot
    // ✅ ถ้า partName ยังว่าง → ลอง parse จาก firstLot ก่อน (lot แรกของเอกสาร)
    if (partName.isEmpty && _looksLikeLotNo(firstLot)) {
      final parsed = _parsePartFromLot(firstLot);
      partNo = partNo.isNotEmpty ? partNo : (parsed['part_no'] ?? '');
      partName = parsed['part_name'] ?? '';
    }

    // ถ้ายังว่างอีก ค่อย fallback ไป currentLot
    if (partName.isEmpty && _looksLikeLotNo(currentLot)) {
      final parsed = _parsePartFromLot(currentLot);
      partNo = partNo.isNotEmpty ? partNo : (parsed['part_no'] ?? '');
      partName = parsed['part_name'] ?? '';
    }

    final staId = (tkDoc['op_sta_id']?.toString() ?? '-').trim();
    final staName = (tkDoc['op_sta_name']?.toString() ?? '-').trim();

    final mcId = (tkDoc['MC_id']?.toString() ?? '-').trim();
    final mcName = (tkDoc['MC_name']?.toString() ?? '-').trim();

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
            Text('Lot No: ${firstLot.isEmpty ? '-' : firstLot}'),
            if (baseLotNo != null && baseLotNo!.trim().isNotEmpty)
              Text(
                'Base Lot: ${baseLotNo!.trim()}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),

            const SizedBox(height: 4),
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
