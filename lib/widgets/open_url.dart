import 'package:url_launcher/url_launcher.dart';

/// باز کردن لینک در مرورگر/برنامه‌ی بیرونی. true اگر باز شد.
Future<bool> openUrl(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// `@username` یا `t.me/...` را به لینک تلگرام تبدیل می‌کند.
String telegramUrl(String handle) {
  final h = handle.trim();
  if (h.startsWith('http') || h.startsWith('tg://')) return h;
  if (h.startsWith('t.me/')) return 'https://$h';
  return 'https://t.me/${h.replaceFirst('@', '')}';
}
