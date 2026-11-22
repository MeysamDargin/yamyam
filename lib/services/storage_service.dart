import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yamyam/ads/ad_ledger.dart';
import 'package:yamyam/models/client_account.dart';

/// ذخیره‌ی محلی با Hive (فقط مقدارهای ساده/Map؛ بدون نیاز به adapter).
class StorageService implements AdKv {
  static const _boxName = 'yamyam_store';

  final Box _box;
  StorageService._(this._box);

  @visibleForTesting
  StorageService.forTesting(Box box) : _box = box;

  static Future<StorageService> open() async {
    await Hive.initFlutter();
    return StorageService._(await Hive.openBox(_boxName));
  }

  // ---------- شناسه‌ی دستگاه (پایه‌ی ساخت ایمیل کلاینت) ----------
  String get deviceId {
    var id = _box.get('device_id') as String?;
    if (id == null) {
      id = const Uuid().v4();
      _box.put('device_id', id);
    }
    return id;
  }

  // ---------- سرور انتخاب‌شده ----------
  int? get selectedServerId => _box.get('selected_server') as int?;

  Future<void> setSelectedServerId(int? id) =>
      id == null ? _box.delete('selected_server') : _box.put('selected_server', id);

  // ---------- کلاینت‌ها (یکی برای هر سرور) ----------
  ClientAccount? account(int serverId) {
    final raw = _box.get('account_$serverId');
    if (raw is! Map) return null;
    try {
      return ClientAccount.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAccount(ClientAccount a) =>
      _box.put('account_${a.serverId}', a.toJson());

  Future<void> removeAccount(int serverId) => _box.delete('account_$serverId');

  // ---------- کش کانفیگ پنل (برای حالت آفلاین) ----------
  String? get cachedConfig => _box.get('config_cache') as String?;
  Future<void> saveConfig(String raw) => _box.put('config_cache', raw);

  // ---------- پلن کاربر (آخرین وضعیت شناخته‌شده؛ برای حالت آفلاین/شروع سریع) ----------
  String? get cachedPlan => _box.get('plan_cache') as String?;
  Future<void> saveCachedPlan(String raw) => _box.put('plan_cache', raw);
  Future<void> clearCachedPlan() => _box.delete('plan_cache');

  // ---------- توکن سفارش‌ها (برای آپلود رسید/لغو؛ فقط روی همین دستگاه) ----------
  String? orderToken(int orderId) => _box.get('order_token_$orderId') as String?;
  Future<void> saveOrderToken(int orderId, String token) =>
      _box.put('order_token_$orderId', token);

  // ---------- دفتر و صف رویدادهای تبلیغات (AdKv) ----------
  @override
  String? read(String key) => _box.get(key) as String?;

  @override
  Future<void> write(String key, String value) => _box.put(key, value);

  // ---------- پیام/آپدیت دیده‌شده ----------
  int get seenMessageId => (_box.get('seen_message') as int?) ?? 0;
  Future<void> setSeenMessageId(int id) => _box.put('seen_message', id);

  int get dismissedUpdateCode => (_box.get('dismissed_update') as int?) ?? 0;
  Future<void> setDismissedUpdateCode(int c) => _box.put('dismissed_update', c);
}
