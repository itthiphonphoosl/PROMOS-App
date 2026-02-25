import 'package:flutter/material.dart';
import 'summary_page.dart';

class SummarySearchPage extends StatefulWidget {
  const SummarySearchPage({super.key});

  @override
  State<SummarySearchPage> createState() => _SummarySearchPageState();
}

class _SummarySearchPageState extends State<SummarySearchPage> {
  final _tkCtrl = TextEditingController();

  @override
  void dispose() {
    _tkCtrl.dispose();
    super.dispose();
  }

  void _open() {
    final tkId = _tkCtrl.text.trim();
    if (tkId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SummaryPage(tkId: tkId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Summary'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _tkCtrl,
              decoration: const InputDecoration(
                labelText: 'TK ID',
                hintText: 'e.g. TK2602240002',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _open(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _open,
                child: const Text('Open Summary'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
