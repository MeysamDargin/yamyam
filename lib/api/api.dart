/// آدرس پنل مدیریت YamYam (همان `yamyam_panel`).
///
/// همه‌ی تنظیمات (سرورهای 3X-UI، توکن‌ها، آپدیت، پیام‌ها و ...) از همین پنل
/// گرفته می‌شود و دیگر هیچ آدرس/توکنی داخل اپ نگه‌داری نمی‌شود.
///
/// یا مقدار را همین‌جا بنویسید، یا موقع اجرا بدهید:
///   flutter run --dart-define=PANEL_URL=https://panel.example.com
const apiServerBaseUrl = String.fromEnvironment(
  'PANEL_URL',
  defaultValue: 'https://admin.dargin.net',
);

/// ساخت Uri از آدرس پایه و مسیر (اسلش اضافه را مدیریت می‌کند).
Uri buildApiUri(
  String baseUrl,
  String endpoint, {
  Map<String, dynamic>? queryParameters,
}) {
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final path = endpoint.startsWith('/') ? endpoint : '/$endpoint';
  return Uri.parse('$base$path').replace(
    queryParameters: queryParameters?.map(
      (key, value) => MapEntry(key, value.toString()),
    ),
  );
}
