import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../core/utils/time_utils.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.liveCounters;
    final historyCounts = controller.historyCounts;
    final sessions = controller.historySessions;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Live session card (in-memory only)
        Card(
          color: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'إحصائيات الجلسة الحية (في الذاكرة)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: controller.startNewLiveSession,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('جلسة جديدة'),
                    ),
                  ],
                ),
                Text(
                  'بداية الجلسة: ${TimeUtils.formatShortLocal(controller.liveSessionStartedAt)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Text(
                  'النموذج المصدر: ${controller.activeModel?.displayName ?? "غير محدد"}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const Divider(height: 20),
                const Text(
                  'عدادات الإطارات الحية (Live Frames)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                _RowMetric('ملتزم', '${live.liveCompliantFrames}', const Color(0xFF4ADE80)),
                _RowMetric('مخالفة', '${live.liveViolationFrames}', const Color(0xFFF87171)),
                _RowMetric('مراجعة (غير مؤكد)', '${live.liveReviewFrames}', const Color(0xFFFBBF24)),
                const Divider(height: 20),
                const Text(
                  'عدادات مرور البوابة (Gate Mode Passages)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ملاحظة: عدد مرات المرور لا يعني التعرف على هوية الأشخاص الفريدين.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 6),
                _RowMetric('مرور ملتزم', '${live.gateCompliantPassages}', const Color(0xFF4ADE80)),
                _RowMetric('مرور مخالف', '${live.gateViolationPassages}', const Color(0xFFF87171)),
                _RowMetric('مرور للمراجعة', '${live.gateReviewPassages}', const Color(0xFFFBBF24)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Optional persisted history card
        Card(
          color: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'السجل التاريخي الاختياري (SQLite)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Chip(
                      label: Text(
                        controller.loggingEnabled ? 'مفعّل' : 'معطّل افتراضياً',
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: controller.loggingEnabled
                          ? const Color(0xFF15803D)
                          : const Color(0xFF334155),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'يحتوي هذا السجل على بيانات نصية مجهولة الهوية فقط (بدون صور أو فيديو أو معرّفات أشخاص).',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 10),
                _RowMetric('إجمالي الملتزمين المسجلين', '${historyCounts['compliant'] ?? 0}', const Color(0xFF4ADE80)),
                _RowMetric('إجمالي المخالفات المسجلة', '${historyCounts['violation'] ?? 0}', const Color(0xFFF87171)),
                _RowMetric('إجمالي حالات المراجعة', '${historyCounts['review'] ?? 0}', const Color(0xFFFBBF24)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await controller.exportCsvAndShare();
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('تصدير CSV مجهول الهوية'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: controller.clearAllHistory,
                      icon: const Icon(Icons.delete_sweep, color: Color(0xFFF87171)),
                      label: const Text('مسح السجل'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Text(
          'الجلسات المحفوظة (${sessions.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 6),
        if (sessions.isEmpty)
          const Card(
            color: Color(0xFF111827),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'لا توجد جلسات محفوظة. لتسجيل الأحداث النصية المجهولة، فعّل خيار التسجيل من شاشة الإعدادات.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          )
        else
          ...sessions.take(15).map(
            (s) => Card(
              color: const Color(0xFF111827),
              child: ListTile(
                dense: true,
                title: Text(
                  'جلسة ${TimeUtils.formatShortLocal(s.startedAt)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                subtitle: Text(
                  'المصدر: ${s.sourceType} • الحالة: ${s.state}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RowMetric extends StatelessWidget {
  const _RowMetric(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
