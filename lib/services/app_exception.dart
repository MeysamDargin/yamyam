/// خطای قابل‌نمایش به کاربر (پیام فارسی).
class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

/// خطای ارتباط با API پنل 3X-UI.
class XuiException extends AppException {
  /// قطعی/تایم‌اوت/خطای SSL — یعنی نمی‌دانیم کلاینت وجود دارد یا نه.
  final bool network;

  /// پنل پاسخ JSON داده ولی `success=false` بوده (مثلاً کلاینت پیدا نشد).
  final bool apiError;

  const XuiException(super.message, {this.network = false, this.apiError = false});
}
