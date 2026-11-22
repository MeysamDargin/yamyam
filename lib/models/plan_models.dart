/// مدل‌های پلن رایگان/طلایی (بلوک `plans` کانفیگ، `servers[].plan`، `/plan/me`).
library;

int _int(dynamic v, [int d = 0]) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
double _double(dynamic v, [double d = 0]) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? d;
String _str(dynamic v) => (v ?? '').toString();
bool _bool(dynamic v, [bool d = false]) =>
    v == null ? d : (v == true || v == 1 || v == 'true');
List<String> _strs(dynamic v) =>
    v is List ? v.map(_str).where((e) => e.isNotEmpty).toList() : const [];
String _faNum(int n) => '$n'.replaceAllMapped(
    RegExp(r'\d'), (m) => String.fromCharCode(0x06F0 + int.parse(m[0]!)));
Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : null;

const _gbBytes = 1024 * 1024 * 1024;

/// پلن رایگان روی «یک سرور» (از `servers[].plan`).
class ServerPlan {
  /// limited | unlimited | gold_only
  final String freeMode;
  final double freeDailyGb;
  final bool freeUnlimited;
  final bool goldEnabled;
  final String badge;

  const ServerPlan({
    this.freeMode = 'limited',
    this.freeDailyGb = 0,
    this.freeUnlimited = true,
    this.goldEnabled = true,
    this.badge = '',
  });

  bool get goldOnly => freeMode == 'gold_only';

  static ServerPlan? fromJson(dynamic raw) {
    final j = _map(raw);
    if (j == null) return null;
    return ServerPlan(
      freeMode: _str(j['free_mode']).isEmpty ? 'limited' : _str(j['free_mode']),
      freeDailyGb: _double(j['free_daily_gb']),
      freeUnlimited: _bool(j['free_unlimited']),
      goldEnabled: _bool(j['gold_enabled'], true),
      badge: _str(j['badge']),
    );
  }
}

class FreePlanInfo {
  final String title;
  final String tagline;
  final double dailyGb;
  final List<String> features;
  final String resetText;
  const FreePlanInfo({
    this.title = 'رایگان',
    this.tagline = '',
    this.dailyGb = 0,
    this.features = const [],
    this.resetText = '',
  });

  factory FreePlanInfo.fromJson(Map<String, dynamic>? j) => FreePlanInfo(
        title: _str(j?['title']).isEmpty ? 'رایگان' : _str(j?['title']),
        tagline: _str(j?['tagline']),
        dailyGb: _double(j?['daily_gb']),
        features: _strs(j?['features']),
        resetText: _str(j?['reset_text']),
      );
}

/// یک بسته‌ی قابل خرید.
class GoldPackage {
  final int id;
  final String title;
  final String description;
  final String badge;
  final bool popular;
  final int price;
  final int oldPrice;
  final int durationDays;
  final double dailyGb; // ۰ = بدون سقف روزانه
  final double totalGb; // ۰ = نامحدود
  final String totalPeriod; // monthly | subscription
  final int limitIp;
  final List<int> servers; // خالی = همه
  final List<String> features;

  const GoldPackage({
    required this.id,
    required this.title,
    this.description = '',
    this.badge = '',
    this.popular = false,
    this.price = 0,
    this.oldPrice = 0,
    this.durationDays = 30,
    this.dailyGb = 0,
    this.totalGb = 0,
    this.totalPeriod = 'monthly',
    this.limitIp = 0,
    this.servers = const [],
    this.features = const [],
  });

  factory GoldPackage.fromJson(Map<String, dynamic> j) => GoldPackage(
        id: _int(j['id']),
        title: _str(j['title']),
        description: _str(j['description']),
        badge: _str(j['badge']),
        popular: _bool(j['popular']),
        price: _int(j['price']),
        oldPrice: _int(j['old_price']),
        durationDays: _int(j['duration_days'], 30),
        dailyGb: _double(j['daily_gb']),
        totalGb: _double(j['total_gb']),
        totalPeriod:
            _str(j['total_period']).isEmpty ? 'monthly' : _str(j['total_period']),
        limitIp: _int(j['limit_ip']),
        servers: ((j['servers'] as List?) ?? const []).map((e) => _int(e)).toList(),
        features: _strs(j['features']),
      );

  bool get hasDiscount => oldPrice > price && price >= 0;
  bool get dailyUnlimited => dailyGb <= 0;
  bool get totalUnlimited => totalGb <= 0;
}

class GoldInfo {
  final String title;
  final String tagline;
  final String badgeText;
  final String promoTitle;
  final String promoText;
  final List<String> features;
  final String terms;
  final List<String> tutorial;
  final String ctaText;
  final String accentHex;
  final bool hideAds;
  final bool showRewardCenter;
  final String supportText;
  final List<GoldPackage> packages;

  const GoldInfo({
    this.title = 'طلایی',
    this.tagline = '',
    this.badgeText = 'VIP',
    this.promoTitle = '',
    this.promoText = '',
    this.features = const [],
    this.terms = '',
    this.tutorial = const [],
    this.ctaText = 'خرید پلن طلایی',
    this.accentHex = '#D4A017',
    this.hideAds = true,
    this.showRewardCenter = false,
    this.supportText = '',
    this.packages = const [],
  });

  factory GoldInfo.fromJson(Map<String, dynamic>? j) => GoldInfo(
        title: _str(j?['title']).isEmpty ? 'طلایی' : _str(j?['title']),
        tagline: _str(j?['tagline']),
        badgeText: _str(j?['badge_text']),
        promoTitle: _str(j?['promo_title']),
        promoText: _str(j?['promo_text']),
        features: _strs(j?['features']),
        terms: _str(j?['terms']),
        tutorial: _strs(j?['tutorial']),
        ctaText:
            _str(j?['cta_text']).isEmpty ? 'خرید پلن طلایی' : _str(j?['cta_text']),
        accentHex:
            _str(j?['accent']).isEmpty ? '#D4A017' : _str(j?['accent']),
        hideAds: _bool(j?['hide_ads'], true),
        showRewardCenter: _bool(j?['show_reward_center']),
        supportText: _str(j?['support_text']),
        packages: ((j?['packages'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => GoldPackage.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  GoldPackage? packageById(int? id) {
    for (final p in packages) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class PaymentInfo {
  final String methodTitle;
  final String cardNumber;
  final String cardNumberPretty;
  final String cardHolder;
  final String bankName;
  final String sheba;
  final String instructions;

  /// image | text | any | none
  final String receipt;
  final bool requirePayerName;
  final bool requirePayerCard;
  final String currency;
  final double maxReceiptMb;
  final String pendingText;
  final String approvedText;
  final String approval; // manual | auto

  const PaymentInfo({
    this.methodTitle = 'کارت به کارت',
    this.cardNumber = '',
    this.cardNumberPretty = '',
    this.cardHolder = '',
    this.bankName = '',
    this.sheba = '',
    this.instructions = '',
    this.receipt = 'any',
    this.requirePayerName = false,
    this.requirePayerCard = false,
    this.currency = 'تومان',
    this.maxReceiptMb = 5,
    this.pendingText = '',
    this.approvedText = '',
    this.approval = 'manual',
  });

  factory PaymentInfo.fromJson(Map<String, dynamic>? j) => PaymentInfo(
        methodTitle: _str(j?['method_title']).isEmpty
            ? 'کارت به کارت'
            : _str(j?['method_title']),
        cardNumber: _str(j?['card_number']),
        cardNumberPretty: _str(j?['card_number_pretty']),
        cardHolder: _str(j?['card_holder']),
        bankName: _str(j?['bank_name']),
        sheba: _str(j?['sheba']),
        instructions: _str(j?['instructions']),
        receipt: _str(j?['receipt']).isEmpty ? 'any' : _str(j?['receipt']),
        requirePayerName: _bool(j?['require_payer_name']),
        requirePayerCard: _bool(j?['require_payer_card']),
        currency: _str(j?['currency']).isEmpty ? 'تومان' : _str(j?['currency']),
        maxReceiptMb: _double(j?['max_receipt_mb'], 5),
        pendingText: _str(j?['pending_text']),
        approvedText: _str(j?['approved_text']),
        approval: _str(j?['approval']).isEmpty ? 'manual' : _str(j?['approval']),
      );

  bool get wantsImage => receipt == 'image' || receipt == 'any';
  bool get wantsTracking => receipt == 'text' || receipt == 'any';
  bool get hasCard => cardNumber.isNotEmpty;
}

class PlanUi {
  final bool showPlanChip;
  final bool upsellBanner;
  final String upsellTitle;
  final String upsellText;
  final bool upsellOnDepleted;
  final bool upsellOnLockedServer;
  final bool goldTheme;
  final int expiryWarningDays;
  // متن‌های قابل ویرایش (جای‌نگهدارها: {plan} و {days}). خالی = پیش‌فرض اپ.
  final String upsellCta,
      upgradeCta,
      depletedCta,
      expiringTitle,
      expiringText,
      expiredTitle,
      expiredText,
      renewCta,
      lockedServerText,
      lockedBadgeText;

  const PlanUi({
    this.showPlanChip = true,
    this.upsellBanner = true,
    this.upsellTitle = '',
    this.upsellText = '',
    this.upsellOnDepleted = true,
    this.upsellOnLockedServer = true,
    this.goldTheme = true,
    this.expiryWarningDays = 5,
    this.upsellCta = '',
    this.upgradeCta = '',
    this.depletedCta = '',
    this.expiringTitle = '',
    this.expiringText = '',
    this.expiredTitle = '',
    this.expiredText = '',
    this.renewCta = '',
    this.lockedServerText = '',
    this.lockedBadgeText = '',
  });

  /// [custom] اگر خالی بود [fallback]؛ سپس `{plan}`/`{days}` جایگزین می‌شود.
  static String fmt(String custom, String fallback, {required String plan, int days = 0}) =>
      (custom.trim().isEmpty ? fallback : custom)
          .replaceAll('{plan}', plan)
          .replaceAll('{days}', _faNum(days));

  factory PlanUi.fromJson(Map<String, dynamic>? j) => PlanUi(
        showPlanChip: _bool(j?['show_plan_chip'], true),
        upsellBanner: _bool(j?['upsell_banner'], true),
        upsellTitle: _str(j?['upsell_title']),
        upsellText: _str(j?['upsell_text']),
        upsellOnDepleted: _bool(j?['upsell_on_depleted'], true),
        upsellOnLockedServer: _bool(j?['upsell_on_locked_server'], true),
        goldTheme: _bool(j?['gold_theme'], true),
        expiryWarningDays: _int(j?['show_expiry_warning_days'], 5),
        upsellCta: _str(j?['upsell_cta']),
        upgradeCta: _str(j?['upgrade_cta']),
        depletedCta: _str(j?['depleted_cta']),
        expiringTitle: _str(j?['expiring_title']),
        expiringText: _str(j?['expiring_text']),
        expiredTitle: _str(j?['expired_title']),
        expiredText: _str(j?['expired_text']),
        renewCta: _str(j?['renew_cta']),
        lockedServerText: _str(j?['locked_server_text']),
        lockedBadgeText: _str(j?['locked_badge_text']),
      );
}

/// بلوک `plans` کانفیگ پنل. وقتی `enabled=false` یعنی اپ مثل قبل رفتار کند.
class PlansInfo {
  final bool enabled;
  final FreePlanInfo free;
  final GoldInfo gold;
  final PaymentInfo payment;
  final PlanUi ui;

  const PlansInfo({
    this.enabled = false,
    this.free = const FreePlanInfo(),
    this.gold = const GoldInfo(),
    this.payment = const PaymentInfo(),
    this.ui = const PlanUi(),
  });

  static const off = PlansInfo();

  factory PlansInfo.fromJson(Map<String, dynamic>? j) {
    if (j == null || !_bool(j['enabled'])) return off;
    return PlansInfo(
      enabled: true,
      free: FreePlanInfo.fromJson(_map(j['free'])),
      gold: GoldInfo.fromJson(_map(j['gold'])),
      payment: PaymentInfo.fromJson(_map(j['payment'])),
      ui: PlanUi.fromJson(_map(j['ui'])),
    );
  }

  /// حداقل یک بسته‌ی قابل خرید و راه پرداخت وجود دارد؟
  bool get canPurchase => enabled && gold.packages.isNotEmpty;
}

/// آنچه باید روی «یک سرور» برای این کاربر برقرار باشد (از `/plan/me`).
class ServerSpec {
  /// free | gold | blocked
  final String mode;
  final String title;
  final int totalBytes; // ۰ = نامحدود
  final String reset; // never | daily | monthly
  final int expiryMs;
  final int expiryDays;
  final int limitIp;
  final bool enabled;
  final int capBytes;
  final String capPeriod;

  const ServerSpec({
    required this.mode,
    this.title = '',
    this.totalBytes = 0,
    this.reset = 'never',
    this.expiryMs = 0,
    this.expiryDays = 0,
    this.limitIp = 0,
    this.enabled = true,
    this.capBytes = 0,
    this.capPeriod = '',
  });

  factory ServerSpec.fromJson(Map<String, dynamic> j) => ServerSpec(
        mode: _str(j['mode']),
        title: _str(j['title']),
        totalBytes: _int(j['total']),
        reset: _str(j['reset']).isEmpty ? 'never' : _str(j['reset']),
        expiryMs: _int(j['expiry_ms']),
        expiryDays: _int(j['expiry_days']),
        limitIp: _int(j['limit_ip']),
        enabled: _bool(j['enabled'], true),
        capBytes: _int(j['cap']),
        capPeriod: _str(j['cap_period']),
      );

  bool get blocked => mode == 'blocked';
  bool get gold => mode == 'gold';
  bool get unlimited => totalBytes <= 0;
  bool get dailyReset => reset == 'daily';
  double get totalGb => totalBytes / _gbBytes;
  double get capGb => capBytes / _gbBytes;
}

class PlanOrder {
  final int id;
  final String status; // awaiting_receipt|pending|approved|rejected|cancelled|expired
  final int packageId;
  final String packageTitle;
  final int amount;
  final String trackingCode;
  final bool hasReceipt;
  final String rejectReason;
  final String createdAt;

  const PlanOrder({
    required this.id,
    required this.status,
    this.packageId = 0,
    this.packageTitle = '',
    this.amount = 0,
    this.trackingCode = '',
    this.hasReceipt = false,
    this.rejectReason = '',
    this.createdAt = '',
  });

  factory PlanOrder.fromJson(Map<String, dynamic> j) => PlanOrder(
        id: _int(j['id']),
        status: _str(j['status']),
        packageId: _int(j['package_id']),
        packageTitle: _str(j['package_title']),
        amount: _int(j['amount']),
        trackingCode: _str(j['tracking_code']),
        hasReceipt: _bool(j['has_receipt']),
        rejectReason: _str(j['reject_reason']),
        createdAt: _str(j['created_at']),
      );

  bool get open => status == 'awaiting_receipt' || status == 'pending';
  bool get needsReceipt => status == 'awaiting_receipt';
  bool get approved => status == 'approved';
}

/// وضعیت پلن کاربر (پاسخ `/plan/me` و `/plan/sync`).
class UserPlan {
  final bool enabled;
  final bool gold;
  final String title;
  final String packageTitle;
  final int expiresMs;
  final int startedMs;
  final int daysLeft;
  final double dailyGb;
  final double totalGb;
  final String totalPeriod;
  final bool expired; // اشتراک طلایی داشته و تمام شده
  final Map<int, ServerSpec> servers;
  final List<PlanOrder> orders;

  /// آیا پاسخ همگام‌سازی روی کلاینت‌ها چیزی را تغییر داد؟ (فقط `/plan/sync`)
  final bool changed;

  const UserPlan({
    this.enabled = false,
    this.gold = false,
    this.title = '',
    this.packageTitle = '',
    this.expiresMs = 0,
    this.startedMs = 0,
    this.daysLeft = 0,
    this.dailyGb = 0,
    this.totalGb = 0,
    this.totalPeriod = 'monthly',
    this.expired = false,
    this.servers = const {},
    this.orders = const [],
    this.changed = false,
  });

  static const free = UserPlan();

  factory UserPlan.fromJson(Map<String, dynamic> j) {
    final plan = _map(j['plan']) ?? const {};
    final servers = <int, ServerSpec>{};
    (_map(j['servers']) ?? const {}).forEach((k, v) {
      final id = int.tryParse(k);
      final m = _map(v);
      if (id != null && m != null) servers[id] = ServerSpec.fromJson(m);
    });
    var changed = false;
    final applied = _map(j['applied']);
    (_map(applied?['servers']) ?? const {}).forEach((_, v) {
      if (v is Map && v['changed'] == true && v['ok'] != false) changed = true;
    });
    return UserPlan(
      enabled: _bool(j['enabled']),
      gold: _str(plan['kind']) == 'gold',
      title: _str(plan['title']),
      packageTitle: _str(plan['package_title']),
      expiresMs: _int(plan['expires_ms']),
      startedMs: _int(plan['started_ms']),
      daysLeft: _int(plan['days_left']),
      dailyGb: _double(plan['daily_gb']),
      totalGb: _double(plan['total_gb']),
      totalPeriod:
          _str(plan['total_period']).isEmpty ? 'monthly' : _str(plan['total_period']),
      expired: _bool(plan['expired']),
      servers: servers,
      orders: ((j['orders'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => PlanOrder.fromJson(e.cast<String, dynamic>()))
          .toList(),
      changed: changed,
    );
  }

  DateTime? get expiresAt =>
      expiresMs > 0 ? DateTime.fromMillisecondsSinceEpoch(expiresMs) : null;

  PlanOrder? get openOrder {
    for (final o in orders) {
      if (o.open) return o;
    }
    return null;
  }

  bool get hasOpenOrder => openOrder != null;
}

/// نتیجه‌ی ثبت سفارش: خود سفارش + توکن مخصوص آن (برای آپلود رسید/لغو).
class OrderTicket {
  final PlanOrder order;
  final String token;
  const OrderTicket(this.order, this.token);
}
