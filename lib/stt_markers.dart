bool isNonSpeechSttMarker(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;

  var rest = trimmed;
  final marker = RegExp(r'^\[[^\[\]]+\]');
  while (rest.isNotEmpty) {
    final match = marker.firstMatch(rest);
    if (match == null) return false;
    rest = rest.substring(match.end).trimLeft();
  }
  return true;
}
