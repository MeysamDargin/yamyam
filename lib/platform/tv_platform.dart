import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// تشخیص اندروید تی‌وی. قبل از `runApp` یک‌بار صدا زده می‌شود.
class TvPlatform {
  static bool isTv = false;

  static Future<void> detect() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final features = info.systemFeatures;
      isTv = features.contains('android.hardware.type.television') ||
          features.contains('android.software.leanback');
    } catch (_) {
      isTv = false;
    }
  }
}
