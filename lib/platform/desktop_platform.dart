import 'package:flutter/material.dart';

/// ویندوز، لینوکس و مک: اپ داخل پنجره‌ای به اندازهٔ گوشی اجرا می‌شود و موس دارد.
bool isDesktopPlatform(BuildContext context) {
  switch (Theme.of(context).platform) {
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}
