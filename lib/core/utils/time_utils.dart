class TimeUtils {
  TimeUtils._();

  /// Returns current UTC timestamp in ISO-8601 format.
  static String nowIsoUtc() => DateTime.now().toUtc().toIso8601String();

  static DateTime parseUtc(String isoString) => DateTime.parse(isoString).toUtc();

  static String formatShortLocal(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }
}
