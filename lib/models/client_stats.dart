/// وضعیت کلاینت از `GET /panel/api/clients/traffic/{email}`.
enum AccountState { active, disabled, expired, depleted }

class ClientStats {
  final String email;
  final String uuid;
  final bool enable;
  final int up; // bytes
  final int down; // bytes
  final int total; // bytes (۰ = نامحدود)
  final int expiryTime; // میلی‌ثانیه‌ی epoch (۰ = نامحدود، منفی = شروع پس از اولین اتصال)
  final int lastOnline; // میلی‌ثانیه
  final DateTime fetchedAt;

  const ClientStats({
    required this.email,
    required this.uuid,
    required this.enable,
    required this.up,
    required this.down,
    required this.total,
    required this.expiryTime,
    required this.lastOnline,
    required this.fetchedAt,
  });

  factory ClientStats.fromJson(Map<String, dynamic> j) {
    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;
    return ClientStats(
      email: '${j['email'] ?? ''}',
      uuid: '${j['uuid'] ?? ''}',
      enable: j['enable'] != false,
      up: i(j['up']),
      down: i(j['down']),
      total: i(j['total']),
      expiryTime: i(j['expiryTime']),
      lastOnline: i(j['lastOnline']),
      fetchedAt: DateTime.now(),
    );
  }

  int get used => up + down;
  bool get unlimitedTraffic => total <= 0;
  bool get unlimitedTime => expiryTime == 0;

  /// مدت‌زمانی که هنوز شروع نشده (منفی = روز بعد از اولین اتصال)
  bool get startsOnFirstUse => expiryTime < 0;

  int get remainingBytes => unlimitedTraffic ? -1 : (total - used).clamp(0, total);

  double get usedFraction =>
      unlimitedTraffic ? 0 : (used / total).clamp(0.0, 1.0).toDouble();

  /// درصد حجم مصرف‌شده؛ برای نامحدود معنی ندارد.
  int? get usedPercent => unlimitedTraffic ? null : (usedFraction * 100).round();

  DateTime? get expiryDate => expiryTime > 0
      ? DateTime.fromMillisecondsSinceEpoch(expiryTime)
      : null;

  bool get isExpired =>
      expiryTime > 0 && DateTime.now().millisecondsSinceEpoch >= expiryTime;

  bool get isDepleted => !unlimitedTraffic && used >= total;

  /// روز باقی‌مانده (null = نامحدود)
  int? get daysLeft {
    if (startsOnFirstUse) return (-expiryTime / 86400000).ceil();
    final d = expiryDate;
    if (d == null) return null;
    final diff = d.difference(DateTime.now());
    return diff.isNegative ? 0 : (diff.inMinutes / 1440).ceil();
  }

  AccountState get state {
    if (!enable) return AccountState.disabled;
    if (isExpired) return AccountState.expired;
    if (isDepleted) return AccountState.depleted;
    return AccountState.active;
  }

  bool get canConnect => state == AccountState.active;
}
