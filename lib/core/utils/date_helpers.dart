import 'package:easy_localization/easy_localization.dart';

class DateHelpers {
  DateHelpers._();
  static String formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
  static String timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1)  return 'time.justNow'.tr();
    if (diff.inMinutes < 60) return 'time.minsAgo'.tr(namedArgs: {'n': '${diff.inMinutes}'});
    if (diff.inHours   < 24) return 'time.hoursAgo'.tr(namedArgs: {'n': '${diff.inHours}'});
    if (diff.inDays    == 1) return 'time.yesterday'.tr();
    if (diff.inDays    < 7)  return 'time.daysAgo'.tr(namedArgs: {'n': '${diff.inDays}'});
    return formatDate(d);
  }
  static String formatTimer(Duration d) {
    if (d.isNegative) return '00:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
