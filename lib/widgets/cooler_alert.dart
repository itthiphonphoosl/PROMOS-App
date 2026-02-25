import 'dart:async';
import 'package:flutter/material.dart';

enum CoolerAlertType { success, error, warning, info }

class CoolerAlert {
  static void show(
    BuildContext context, {
    String title = 'แจ้งเตือน',
    required String message,
    CoolerAlertType type = CoolerAlertType.info,
    Duration duration = const Duration(seconds: 2),
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
        onTap: remove, // แตะตรงไหนก็หาย
        child: Material(
          // ถ้าไม่อยากให้พื้นหลังมืด เปลี่ยนเป็น Colors.transparent
          color: Colors.black.withOpacity(0.18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: _AlertCard(
                title: title,
                message: message,
                icon: meta.icon,
                borderColor: meta.borderColor,
                bgColor: meta.bgColor,
                iconBg: meta.iconBg,
                onClose: remove,
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    // หายเองใน 2 วิ
    Timer(duration, remove);
  }

  static _AlertMeta _meta(CoolerAlertType type) {
    switch (type) {
      case CoolerAlertType.success:
        return _AlertMeta(
          icon: Icons.check_circle_rounded,
          borderColor: const Color(0xFF2ECC71),
          bgColor: const Color(0xFFEAFBF1),
          iconBg: const Color(0xFF2ECC71),
        );
      case CoolerAlertType.error:
        return _AlertMeta(
          icon: Icons.cancel_rounded,
          borderColor: const Color(0xFFE74C3C),
          bgColor: const Color(0xFFFFECEA),
          iconBg: const Color(0xFFE74C3C),
        );
      case CoolerAlertType.warning:
        return _AlertMeta(
          icon: Icons.warning_rounded,
          borderColor: const Color(0xFFF39C12),
          bgColor: const Color(0xFFFFF3DE),
          iconBg: const Color(0xFFF39C12),
        );
      case CoolerAlertType.info:
      default:
        return _AlertMeta(
          icon: Icons.info_rounded,
          borderColor: const Color(0xFF3498DB),
          bgColor: const Color(0xFFEAF4FF),
          iconBg: const Color(0xFF3498DB),
        );
    }
  }
}

class _AlertMeta {
  final IconData icon;
  final Color borderColor;
  final Color bgColor;
  final Color iconBg;

  _AlertMeta({
    required this.icon,
    required this.borderColor,
    required this.bgColor,
    required this.iconBg,
  });
}

class _AlertCard extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color borderColor;
  final Color bgColor;
  final Color iconBg;
  final VoidCallback onClose;

  const _AlertCard({
    required this.title,
    required this.message,
    required this.icon,
    required this.borderColor,
    required this.bgColor,
    required this.iconBg,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(
        // กันการ์ดแผ่เต็มจอ
        minWidth: 260,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withOpacity(0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // สำคัญ: ไม่ให้ Row ยืด
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),

          // เปลี่ยนจาก Expanded เป็น Flexible + Column mainAxisSize.min
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min, // สำคัญ: ไม่ให้ Column ยืดสูง
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black.withOpacity(0.75),
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
