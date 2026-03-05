class FormatUtils {
  static String formatDuration(int minutes) {
    if (minutes < 60) return "$minutes min";

    final int days = minutes ~/ 1440;
    final int hours = (minutes % 1440) ~/ 60;
    final int mins = minutes % 60;

    String res = "";
    if (days > 0) res += "${days}d ";
    if (hours > 0) res += "${hours}h ";
    if (mins > 0 || res.isEmpty) res += "${mins}min";

    return res.trim();
  }
}
