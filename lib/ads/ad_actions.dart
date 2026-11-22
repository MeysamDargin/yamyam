import 'package:flutter/material.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/widgets/ad_media.dart';
import 'package:yamyam/ads/widgets/ad_web_page.dart';
import 'package:yamyam/widgets/open_url.dart';

/// کلیک روی تبلیغ: آمار + پیکسل + اجرای «عمل کلیک» تعریف‌شده در پنل.
Future<void> openAd(BuildContext context, AdItem ad, String placement) async {
  final ads = adsOf(context);
  ads.recordClick(ad, placement);
  if (!ad.clickable) return;
  final url = ad.clickUrl.trim();
  switch (ad.clickAction) {
    case 'in_app':
      final scheme = Uri.tryParse(url)?.scheme ?? '';
      if (scheme == 'http' || scheme == 'https') {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AdWebPage(url: url, title: ad.headline),
        ));
      } else {
        await openUrl(url);
      }
    case 'telegram':
      await openUrl(telegramUrl(url));
    case 'store':
      if (!await openUrl(url)) {
        // market://details?id=pkg → صفحه‌ی وب گوگل‌پلی
        final id = Uri.tryParse(url)?.queryParameters['id'];
        if (url.startsWith('market://') && id != null) {
          await openUrl('https://play.google.com/store/apps/details?id=$id');
        }
      }
    case 'open_url':
      await openUrl(url);
    default:
      break;
  }
}
