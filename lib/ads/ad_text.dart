import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/core/ui.dart';

/// متن فارسی جایزه (نوع + مقدار)
String rewardText(String type, double amount) {
  String n(num v) => faDigits(v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1));
  switch (type) {
    case 'traffic_mb':
      return amount >= 1024 ? '${n(amount / 1024)} گیگابایت حجم' : '${n(amount)} مگابایت حجم';
    case 'days':
      return '${n(amount)} روز اشتراک';
    case 'no_ads_minutes':
      return amount >= 60 ? '${n(amount / 60)} ساعت بدون تبلیغ' : '${n(amount)} دقیقه بدون تبلیغ';
    case 'coins':
      return '${n(amount)} سکه';
    default:
      return '';
  }
}

String rewardLabel(AdItem a) => rewardText(a.rewardType, a.rewardAmount);

/// برچسب تبلیغ (سفارشی یا سراسری)
String adBadge(AdItem a, AdsSettings s) => a.badgeText.isNotEmpty ? a.badgeText : s.adLabel;
