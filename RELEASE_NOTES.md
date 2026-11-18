# ملاحظات الإصدار v1.0.0 — SafeZone AI Mobile

## الملخص
إصدار جاهز للتشغيل المحلي الكامل (Offline-First) على Android 8.0+ (مختبر معمارياً لـ Samsung Galaxy Z Flip3 وAndroid 11+).

## القيود المعروفة والخطوات الميدانية المطلوبة
1. يتطلب تشغيل `flutter pub get` و`flutter test` و`flutter build apk --release` محلياً على جهاز يحتوي Flutter SDK وAndroid SDK.
2. لا يتضمن التطبيق ملفات أوزان `.tflite` مدمجة؛ يجب تصدير `best_mask_v4.pt` باستخدام `tools/export_mask_v4_colab.py` واستيراده من داخل التطبيق.
3. وضع البوابة (Gate Mode) يجمع الأدلة الزمنية لكل مرور ولا يدّعي التعرف على هوية الأشخاص الفريدين.
4. يجب مراجعة رخصة Ultralytics AGPL-3.0 قبل أي استخدام تجاري مغلق للنماذج المصدّرة عبر Ultralytics.
