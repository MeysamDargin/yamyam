import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:yamyam/platform/tv_platform.dart';

/// پیشوند شناسهٔ کاربر در پنل.
///
/// گوشی `yy`، اندروید تی‌وی `yytv`، ویندوز `yywin`.
/// لینوکس و مک همان پیشوند گوشی را می‌گیرند.
String clientIdPrefix({bool? windows, bool? tv}) {
  if (tv ?? TvPlatform.isTv) return 'yytv';
  final win = windows ?? (!kIsWeb && Platform.isWindows);
  if (win) return 'yywin';
  return 'yy';
}
