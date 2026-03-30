// Web: read token from current page URL (e.g. ?token=xxx).
import 'dart:html' as html;

String? getResetTokenFromUrl() {
  try {
    final uri = Uri.tryParse(html.window.location.href);
    final token = uri?.queryParameters['token'];
    return (token != null && token.isNotEmpty) ? token : null;
  } catch (_) {
    return null;
  }
}
