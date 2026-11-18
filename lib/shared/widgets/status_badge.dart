import 'package:flutter/material.dart';

import '../../features/safety/domain/safety_status.dart';

class SafetyStatusBanner extends StatelessWidget {
  const SafetyStatusBanner({
    super.key,
    required this.status,
    required this.reason,
    this.confidence,
    this.primaryLabel,
  });

  final SafetyStatus status;
  final String reason;
  final double? confidence;
  final String? primaryLabel;

  Color get _backgroundColor {
    switch (status) {
      case SafetyStatus.compliant:
        return const Color(0xFF14532D);
      case SafetyStatus.violation:
        return const Color(0xFF7F1D1D);
      case SafetyStatus.review:
        return const Color(0xFF78350F);
      case SafetyStatus.noConfirmedEvent:
        return const Color(0xFF1E293B);
    }
  }

  Color get _accentColor {
    switch (status) {
      case SafetyStatus.compliant:
        return const Color(0xFF4ADE80);
      case SafetyStatus.violation:
        return const Color(0xFFF87171);
      case SafetyStatus.review:
        return const Color(0xFFFBBF24);
      case SafetyStatus.noConfirmedEvent:
        return const Color(0xFF94A3B8);
    }
  }

  IconData get _icon {
    switch (status) {
      case SafetyStatus.compliant:
        return Icons.verified_user;
      case SafetyStatus.violation:
        return Icons.warning_amber_rounded;
      case SafetyStatus.review:
        return Icons.help_outline_rounded;
      case SafetyStatus.noConfirmedEvent:
        return Icons.face_retouching_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accentColor.withOpacity(0.6), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(_icon, color: _accentColor, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.arabicLabel,
                  style: TextStyle(
                    color: _accentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (confidence != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${(confidence! * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: _accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
