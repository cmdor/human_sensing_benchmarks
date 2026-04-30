String formatTimeOfDay(DateTime t) {
  final loc = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(loc.hour)}:${two(loc.minute)}:${two(loc.second)}';
}

String formatHms(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}

