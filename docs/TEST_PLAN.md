# SafeZone AI Mobile — Test Plan

Tests require actual evidence. UI checkboxes are not an automated test runner.

| ID | Area | Procedure | Expected | Phase |
|---|---|---|---|---|
| T01 | التأسيس | flutter analyze + flutter test | لا أخطاء تحليل/اختبارات | P0 |
| T02 | الجهاز | تثبيت debug APK على Z Flip3 | فتح وعودة دون انهيار | P1 |
| T03 | الكاميرا | أمامية/خلفية + تشغيل/إيقاف | معاينة صحيحة ولا احتكار جلسة | P1 |
| T04 | الطي والاتجاه | تغيير الاتجاه والطي/الفتح | لا تشوه أو قلب خاطئ | P1 |
| T05 | الاستيراد | ملف .tflite صالح من Files | نسخ خاص وفحص SHA-256 | P2 |
| T06 | إدخال معطوب | ملف وهمي/غير متوافق | رفض آمن برسالة مفهومة | P2 |
| T07 | تبديل دون APK | النموذجان A ثم B ثم A | كل التبديلات ناجحة دون إعادة بناء | P2 |
| T08 | استرجاع التفعيل | فشل B مع A يعمل | يعود A تلقائياً | P2 |
| T09 | الاستمرار | أعد تشغيل التطبيق | النموذج النشط محفوظ | P2 |
| T10 | مطابقة .pt/.tflite | صور مرجعية للفئات الثلاث | توثيق الفروق وقراراتها | P3 |
| T11 | حالات الوجه | صحيح/غياب/خاطئ/جانبي/مخفي | REVIEW بدلاً من اختراع حكم | P3 |
| T12 | الأداء | CPU/GPU و10–15 دقيقة | FPS/p95/ذاكرة حقيقية وتبريد | P4 |
| T13 | عدم تراكم الإطارات | كاميرا 30FPS + inference أبطأ | طابور محدود وأحدث إطار فقط | P4 |
| T14 | مرور البوابة المرجعي | 3 مرات: مخالفتان والتزام | 3 أحداث مؤكدة بلا تكرار | P5 |
| T15 | مرور واقعي موسع | شخصان / حجب / خروج | تقرير false positives/negatives | P5 |
| T16 | الخصوصية | الشبكة مغلقة + نظام الملفات | لا صور وفيديو أو رفع بيانات | P1–P7 |
| T17 | السجل الاختياري | تسجيل مغلق ثم مفعّل | لا تاريخ دون موافقة | P6 |
| T18 | بدء تجربة جديدة | ابدأ جلسة دون حذف التاريخ | عدادات الجلسة فقط تُصفّر | P6 |
| T19 | مراجعة غير مؤكدة | لا دليل كافٍ | تُعرض REVIEW لا تختفي | P3–P6 |
| T20 | تسليم | APK release + import model v5 | تبديل دون إعادة تثبيت | P7 |

## Definition of Done
- `flutter analyze` and appropriate tests pass; share actual results.
- On-device testing is documented, not assumed.
- No hidden media recording or automatic uploads.
- Compatible model switching is demonstrated on Z Flip3 without rebuilding.
- Errors, REVIEW decisions, regressions and remaining limitations are documented.
- Git commit or backup exists before moving to next stage.

## Performance measurements
Collect inference FPS, preview FPS, median/p95 latency, dropped frames, RAM and sustained-operation behavior. Compare CPU/GPU only if the runtime/delegate actually supports the accelerator.
