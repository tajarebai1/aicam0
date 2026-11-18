import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/core/constants/app_constants.dart';
import 'package:safezone_mobile/core/utils/hash_utils.dart';
import 'package:safezone_mobile/core/utils/time_utils.dart';

void main() {
  group('P00 — Foundation & Utilities', () {
    test('default mask class mapping covers all three required labels', () {
      expect(AppConstants.defaultMaskClassMapping['with_mask'], 'compliant');
      expect(AppConstants.defaultMaskClassMapping['without_mask'], 'violation');
      expect(AppConstants.defaultMaskClassMapping['mask_weared_incorrect'], 'violation');
    });

    test('TimeUtils produces valid ISO-8601 UTC timestamps', () {
      final iso = TimeUtils.nowIsoUtc();
      expect(iso.endsWith('Z'), isTrue);
      final parsed = TimeUtils.parseUtc(iso);
      expect(parsed.isUtc, isTrue);
    });

    test('HashUtils computes deterministic SHA-256 hex digest', () {
      final digest = HashUtils.sha256Bytes([1, 2, 3, 4]);
      expect(digest.length, 64);
      expect(digest, HashUtils.sha256Bytes([1, 2, 3, 4]));
    });
  });
}
