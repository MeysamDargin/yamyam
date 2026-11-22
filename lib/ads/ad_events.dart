/// صف رویدادهای تبلیغات (نمایش، کلیک، ...) با ارسال «دسته‌ای» به پنل
/// تا مصرف شبکه‌ی کاربر حداقل باشد. صف روی دیسک ذخیره می‌شود و با بسته شدن اپ از بین نمی‌رود.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yamyam/ads/ad_ledger.dart';

class AdEventQueue {
  AdEventQueue(this._kv, {required this.endpoint, http.Client? client})
      : _client = client ?? http.Client();

  static const _key = 'ads_events';
  final AdKv _kv;
  final Uri endpoint;
  final http.Client _client;

  /// "adId|event|placement" → تعداد
  final Map<String, int> _pending = {};
  bool _flushing = false;

  void load() {
    try {
      final raw = _kv.read(_key);
      if (raw == null) return;
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      m.forEach((k, v) {
        if (v is num && v > 0) _pending[k] = v.toInt();
      });
    } catch (_) {}
  }

  int get pending => _pending.length;

  void add(int adId, String event, String placement) {
    final k = '$adId|$event|$placement';
    _pending[k] = (_pending[k] ?? 0) + 1;
    _persist();
  }

  void _persist() => unawaited(_kv.write(_key, jsonEncode(_pending)));

  /// ارسال. در خطا (شبکه/۴۲۹) صف حفظ می‌شود و بعداً دوباره تلاش می‌شود.
  Future<bool> flush() async {
    if (_flushing || _pending.isEmpty) return true;
    _flushing = true;
    try {
      while (_pending.isNotEmpty) {
        final batch = <String, int>{};
        final items = <Map<String, dynamic>>[];
        for (final e in _pending.entries) {
          if (items.length >= 190) break;
          final p = e.key.split('|');
          if (p.length != 3) {
            batch[e.key] = e.value; // کلید خراب: دور بریز
            continue;
          }
          var left = e.value;
          while (left > 0) {
            final c = left > 100 ? 100 : left;
            items.add({
              'ad_id': int.tryParse(p[0]) ?? 0,
              'event': p[1],
              'placement': p[2],
              'count': c,
            });
            left -= c;
          }
          batch[e.key] = e.value;
        }
        if (items.isEmpty) {
          batch.keys.forEach(_pending.remove);
          continue;
        }
        final ok = await _post(items);
        if (!ok) return false;
        // فقط همان مقدارِ ارسال‌شده کم می‌شود (اگر هم‌زمان رویداد جدیدی آمده باقی بماند)
        batch.forEach((k, sent) {
          final cur = (_pending[k] ?? 0) - sent;
          if (cur > 0) {
            _pending[k] = cur;
          } else {
            _pending.remove(k);
          }
        });
        _persist();
      }
      return true;
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _post(List<Map<String, dynamic>> events) async {
    try {
      final res = await _client
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'events': events}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      // خطای دائمی (مثلاً ۴۲۲): صف را پاک کن تا برای همیشه گیر نکند. ۴۲۹ و ۵xx بعداً.
      if (res.statusCode == 422 || res.statusCode == 400) {
        debugPrint('ad events rejected (${res.statusCode})');
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}

/// پیکسل ردیابی شخص ثالث (fire-and-forget).
Future<void> firePixel(http.Client client, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return;
  try {
    await client.get(uri).timeout(const Duration(seconds: 6));
  } catch (_) {}
}
