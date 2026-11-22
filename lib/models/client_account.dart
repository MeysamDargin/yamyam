/// کلاینتی که اپ برای این کاربر روی یک سرور 3X-UI ساخته (در Hive ذخیره می‌شود).
class ClientAccount {
  final int serverId;
  final String email; // شناسه‌ی کلاینت در 3X-UI
  final String uuid;
  final String baseUrl; // برای تشخیص تغییر سرور توسط مدیر
  final int inboundId;
  final DateTime createdAt;

  /// لینک اتصال (vless://...) کش‌شده؛ با آن اتصال بدون هیچ درخواست شبکه‌ای
  /// شروع می‌شود. اگر کار نکرد دوباره از پنل گرفته می‌شود.
  final String? link;

  const ClientAccount({
    required this.serverId,
    required this.email,
    required this.uuid,
    required this.baseUrl,
    required this.inboundId,
    required this.createdAt,
    this.link,
  });

  ClientAccount withLink(String? link) => ClientAccount(
        serverId: serverId,
        email: email,
        uuid: uuid,
        baseUrl: baseUrl,
        inboundId: inboundId,
        createdAt: createdAt,
        link: link,
      );

  Map<String, dynamic> toJson() => {
        'serverId': serverId,
        'email': email,
        'uuid': uuid,
        'baseUrl': baseUrl,
        'inboundId': inboundId,
        'createdAt': createdAt.toIso8601String(),
        if (link != null) 'link': link,
      };

  factory ClientAccount.fromJson(Map<dynamic, dynamic> j) => ClientAccount(
        serverId: (j['serverId'] as num).toInt(),
        email: j['email'] as String,
        uuid: (j['uuid'] ?? '') as String,
        baseUrl: (j['baseUrl'] ?? '') as String,
        inboundId: (j['inboundId'] as num).toInt(),
        createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
        link: j['link'] is String && (j['link'] as String).isNotEmpty
            ? j['link'] as String
            : null,
      );
}
