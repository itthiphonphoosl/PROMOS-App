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

    // ดึง current_lots จาก active scan
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
            tkDoc: {
              'part_no': item['lot_no']?.toString() ?? '',
              'op_sta_id': item['op_sta_id']?.toString() ?? '',
              'op_sta_name': item['op_sta_name']?.toString() ?? '',
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
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.pending_actions,
                          color: Colors.orange,
                        ),
                      ),
                      title: Text(
                        item['tk_id']?.toString() ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('SC: ${item['op_sc_id'] ?? '-'}'),
                          Text(
                            'Station: ${item['op_sta_id'] ?? '-'} • MC: ${item['MC_id'] ?? '-'}',
                          ),
                          Text(
                            'เริ่ม: ${_formatDate(item['op_sc_ts']?.toString())}',
                          ),
                        ],
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => _goFinish(item),
                        child: const Text('Finish'),
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
