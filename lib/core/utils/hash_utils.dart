import 'dart:io';
import 'package:crypto/crypto.dart';

class HashUtils {
  HashUtils._();

  /// Computes lowercase hex SHA-256 digest of a file using streaming I/O.
  static Future<String> sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Computes lowercase hex SHA-256 digest of raw bytes.
  static String sha256Bytes(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }
}
