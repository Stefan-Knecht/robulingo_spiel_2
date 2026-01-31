import 'dart:html' as html;

String? getCookieValue(String name) {
  final all = html.document.cookie ?? '';
  if (all.isEmpty) return null;
  for (final part in all.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    final key = trimmed.substring(0, idx).trim();
    if (key != name) continue;
    final value = trimmed.substring(idx + 1);
    return Uri.decodeComponent(value);
  }
  return null;
}

void setCookieValue(String name, String value, {int maxAgeDays = 365}) {
  final maxAgeSeconds = maxAgeDays * 24 * 60 * 60;
  final encoded = Uri.encodeComponent(value);
  html.document.cookie =
      '$name=$encoded; max-age=$maxAgeSeconds; path=/; samesite=lax';
}
