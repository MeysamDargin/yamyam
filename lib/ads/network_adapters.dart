/// اتصال شبکه‌های تبلیغاتی ثالث (AdMob, AppLovin, Unity, Meta, Chartboost,
/// تپسل, ادیوری, یکتانت, تپلیغ) به سیستم تبلیغات.
///
/// پنل برای هر شبکه شناسه‌ها و ترتیب Waterfall را می‌دهد؛ اپ برای هر شبکه یک
/// [AdNetworkAdapter] می‌خواهد. SDK هر شبکه نیاز به تنظیمات بومی زمان build دارد
/// (مثلاً App ID در AndroidManifest) و به همین دلیل پیش‌فرض هیچ adapter ای ثبت نیست:
/// تبلیغ‌هایی که منبعشان شبکه‌ی «ثبت‌نشده» است نادیده گرفته می‌شوند و Waterfall
/// خودکار به منبع بعدی (معمولاً تبلیغات اختصاصی) می‌رود.
///
/// نمونه‌ی ثبت یک adapter (بعد از افزودن SDK و تنظیم manifest):
/// ```dart
/// AdNetworks.register(MyAdMobAdapter());
/// ```
library;

import 'package:flutter/widgets.dart';
import 'package:yamyam/ads/ad_models.dart';

/// نتیجه‌ی نمایش تمام‌صفحه‌ی یک تبلیغ شبکه
class NetworkShowResult {
  final bool shown;
  final bool completed; // تا انتها دیده شد / جایزه‌ی SDK فعال شد
  final bool clicked;
  const NetworkShowResult({this.shown = false, this.completed = false, this.clicked = false});
}

abstract class AdNetworkAdapter {
  /// شناسه‌ی شبکه مطابق پنل: admob, applovin, unity, meta, chartboost, tapsell, adivery, yektanet, tapligh
  String get id;

  /// SDK آماده است؟
  bool get available;

  bool supports(String format) => true;

  Future<void> initialize(NetworkCreds creds, {required bool testMode});

  /// ویجت بنر/بومی؛ null یعنی نشد (Waterfall ادامه می‌یابد).
  Widget? buildInline(
    BuildContext context,
    AdItem ad,
    String unitId, {
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
    required VoidCallback onClick,
  });

  /// نمایش تمام‌صفحه (Interstitial / Rewarded / App Open)
  Future<NetworkShowResult> showFullscreen(BuildContext context, AdItem ad, String unitId);
}

abstract final class AdNetworks {
  static final Map<String, AdNetworkAdapter> _all = {};

  static void register(AdNetworkAdapter a) => _all[a.id] = a;
  static void unregister(String id) => _all.remove(id);
  static AdNetworkAdapter? of(String id) => _all[id];
  static Iterable<AdNetworkAdapter> get registered => _all.values;

  static bool canServe(AdItem ad) {
    final a = _all[ad.network];
    return a != null && a.available && a.supports(ad.format);
  }
}
