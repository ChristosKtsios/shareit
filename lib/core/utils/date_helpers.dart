class DateHelpers {
  DateHelpers._();
  static String formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
  static String timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1)  return 'μόλις τώρα';
    if (diff.inMinutes < 60) return 'πριν ${diff.inMinutes} λεπτά';
    if (diff.inHours   < 24) return 'πριν ${diff.inHours} ώρες';
    if (diff.inDays    == 1) return 'χθες';
    if (diff.inDays    < 7)  return 'πριν ${diff.inDays} μέρες';
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
