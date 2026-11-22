import 'package:flutter/material.dart';

/// فونت پیش‌فرض اپ. TextStyleهایی که مستقیم به ButtonStyle داده می‌شوند از تم فونت نمی‌گیرند؛ باید صریح بدهند.
const kAppFont = 'IRANYekan';

/// پالت رنگ سبک iOS (هم‌سو با اسپلش و صفحه‌ی اصلی).
class UiPalette {
  final bool dark;
  const UiPalette(this.dark);

  Color get bg => dark ? Colors.black : const Color(0xFFF2F2F7);
  Color get card => dark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get label => dark ? Colors.white : const Color(0xFF1C1C1E);
  Color get secondary => const Color(0xFF8E8E93);
  Color get separator =>
      dark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA);

  static const blue = Color(0xFF0A84FF);
  static const cyan = Color(0xFF5AC8FA);
  static const green = Color(0xFF34C759);
  static const amber = Color(0xFFFF9F0A);
  static const orange = Color(0xFFFF6B35);
  static const red = Color(0xFFFF453A);

  // پلن طلایی
  static const gold = Color(0xFFD4A017);
  static const goldLight = Color(0xFFF6D365);
  static const goldDeep = Color(0xFFB8860B);
}

/// `#RRGGBB` → رنگ (در صورت نامعتبر بودن [fallback]).
Color parseHexColor(String hex, [Color fallback = UiPalette.gold]) {
  final h = hex.trim().replaceFirst('#', '');
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// قیمت با جداکننده‌ی هزارگان و ارقام فارسی: `۱۵۰٬۰۰۰`
String formatMoney(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('٬');
    b.write(s[i]);
  }
  return faDigits(b.toString());
}

/// حجم بر حسب گیگابایت (مثلاً `۲٫۵ گیگابایت` / `نامحدود`).
String gbText(double gb) {
  if (gb <= 0) return 'نامحدود';
  final t = gb == gb.roundToDouble() ? gb.round().toString() : gb.toStringAsFixed(1);
  return '${faDigits(t).replaceAll('.', '٫')} گیگابایت';
}

extension UiContext on BuildContext {
  UiPalette get ui =>
      UiPalette(Theme.of(this).brightness == Brightness.dark);
}

// ---------- قالب‌بندی فارسی ----------
String faDigits(Object? v) {
  const en = '0123456789';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  var s = '$v';
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(en[i], fa[i]);
  }
  return s;
}

String formatBytes(num bytes) {
  const units = ['بایت', 'کیلوبایت', 'مگابایت', 'گیگابایت', 'ترابایت'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final text = i < 2 ? v.round().toString() : v.toStringAsFixed(v >= 100 ? 0 : 1);
  return '${faDigits(text).replaceAll('.', '٫')} ${units[i]}';
}

/// سرعت (بایت بر ثانیه) → مقدار و واحد خوانا؛ مثل برنامه‌های VPN (KB/s و MB/s).
({String value, String unit}) speedParts(double bytesPerSecond) {
  final kb = bytesPerSecond / 1024;
  if (kb < 1000) {
    final text = kb < 10 ? kb.toStringAsFixed(1) : kb.round().toString();
    return (value: faDigits(text).replaceAll('.', '٫'), unit: 'کیلوبایت/ث');
  }
  final mb = kb / 1024;
  return (
    value: faDigits(mb.toStringAsFixed(mb < 10 ? 2 : 1)).replaceAll('.', '٫'),
    unit: 'مگابایت/ث',
  );
}

/// کارت سفید/تیره‌ی مدل iOS برای دیالوگ‌ها و شیت‌ها.
BoxDecoration cardDecoration(BuildContext context, {double radius = 22}) {
  final ui = context.ui;
  return BoxDecoration(
    color: ui.card,
    borderRadius: BorderRadius.circular(radius),
  );
}
