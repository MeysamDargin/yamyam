/// مسیرهای API.
///
/// - [panel*]  : پنل YamYam (FastAPI)
/// - [xui*]    : پنل 3X-UI هر سرور (با توکن Bearer)
abstract final class Endpoint {
  // ---------- YamYam panel ----------
  static const panelHealth = '/health';
  static const panelConfig = '/api/v1/config';
  static const panelAdsEvents = '/api/v1/ads/events';
  static const panelPlanMe = '/api/v1/plan/me';
  static const panelPlanSync = '/api/v1/plan/sync';
  static const panelPlanOrders = '/api/v1/plan/orders';
  static String panelOrderReceipt(int id) => '/api/v1/plan/orders/$id/receipt';
  static String panelOrderCancel(int id) => '/api/v1/plan/orders/$id/cancel';

  // ---------- 3X-UI ----------
  static String xuiInbound(int id) => '/panel/api/inbounds/get/$id';
  static const xuiClientAdd = '/panel/api/clients/add';
  static const xuiClientsBulkAdjust = '/panel/api/clients/bulkAdjust';
  static String xuiClient(String email) =>
      '/panel/api/clients/get/${Uri.encodeComponent(email)}';
  static String xuiClientTraffic(String email) =>
      '/panel/api/clients/traffic/${Uri.encodeComponent(email)}';
  static String xuiClientLinks(String email) =>
      '/panel/api/clients/links/${Uri.encodeComponent(email)}';
}
