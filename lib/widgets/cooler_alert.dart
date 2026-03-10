import 'dart:async';
import 'package:flutter/material.dart';

enum CoolerAlertType { success, error, warning, info }

class CoolerAlert {
  static void show(
    BuildContext context, {
    String title = 'แจ้งเตือน',
    required String message,
    CoolerAlertType type = CoolerAlertType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    bool removed = false;
    late OverlayEntry entry;

    void remove() {
      if (removed) return;
      removed = true;
      entry.remove();
    }

    final meta = _meta(type);

    entry = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: remove,
        child: Material(
          color: Colors.black.withOpacity(0.25),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _AlertCard(
                title: title,
                message: message,
                meta: meta,
                onClose: remove,
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    Timer(duration, remove);
  }

  static _AlertMeta _meta(CoolerAlertType type) {
    switch (type) {
      case CoolerAlertType.success:
        return _AlertMeta(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF2ECC71),
          bgColor: const Color(0xFFEAFBF1),
          borderColor: const Color(0xFF27AE60),
          label: 'สำเร็จ',
        );
      case CoolerAlertType.error:
        return _AlertMeta(
          icon: Icons.cancel_rounded,
          color: const Color(0xFFE74C3C),
          bgColor: const Color(0xFFFFECEA),
          borderColor: const Color(0xFFC0392B),
          label: 'ผิดพลาด',
        );
      case CoolerAlertType.warning:
        return _AlertMeta(
          icon: Icons.warning_rounded,
          color: const Color(0xFFF39C12),
          bgColor: const Color(0xFFFFF8E7),
          borderColor: const Color(0xFFE67E22),
          label: 'แจ้งเตือน',
        );
      case CoolerAlertType.info:
      default:
        return _AlertMeta(
          icon: Icons.info_rounded,
          color: const Color(0xFF3498DB),
          bgColor: const Color(0xFFEAF4FF),
          borderColor: const Color(0xFF2980B9),
          label: 'ข้อมูล',
        );
    }
  }
}

class _AlertMeta {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final Color borderColor;
  final String label;

  _AlertMeta({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.borderColor,
    required this.label,
  });
}

class _AlertCard extends StatelessWidget {
  final String title;
  final String message;
  final _AlertMeta meta;
  final VoidCallback onClose;

  const _AlertCard({
    required this.title,
    required this.message,
    required this.meta,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: meta.bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: meta.borderColor.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: meta.color.withOpacity(0.2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── แถบสีบน ──
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: meta.color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── ไอคอนใหญ่ ──
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: meta.color,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: meta.color.withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(meta.icon, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),

                // ── ข้อความ ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: meta.color.withOpacity(0.9),
                                height: 1.2,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: onClose,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.black.withOpacity(0.4),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF2D3436),
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
