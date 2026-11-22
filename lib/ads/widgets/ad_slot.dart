import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yamyam/ads/ad_actions.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ad_text.dart';
import 'package:yamyam/ads/network_adapters.dart';
import 'package:yamyam/ads/widgets/ad_media.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/widgets/open_url.dart';

// ======================================================================= //
// اسلات: یک جایگاه ثابت در صفحه (بنر / بومی / متنی / HTML)
// ======================================================================= //
/// هر جایگاه را به ازای [placement] از روی کانفیگ پنل پر می‌کند؛ اگر تبلیغی نباشد
/// هیچ فضایی اشغال نمی‌کند. بنرها طبق `banner_refresh_sec` می‌چرخند.
///
/// نکته: داخل این ویجت‌ها LayoutBuilder نیست (چون صفحه‌ی اصلی IntrinsicHeight دارد).
class AdSlot extends StatefulWidget {
  final String placement;
  final EdgeInsetsGeometry padding;

  /// نوار چسبان پایین صفحه (با SafeArea و پس‌زمینه)
  final bool sticky;

  /// لینک «حذف تبلیغات» (اگر در پنل تنظیم شده) زیر تبلیغ نشان داده شود
  final bool showRemove;

  const AdSlot({
    super.key,
    required this.placement,
    this.padding = EdgeInsets.zero,
    this.sticky = false,
    this.showRemove = false,
  });

  @override
  State<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends State<AdSlot> {
  late final _ads = adsOf(context);
  AdItem? _ad;
  bool _impressed = false;
  Timer? _timer;
  int _timerSec = -1;
  bool _init = false;

  AdItem? _pick({Set<int> exclude = const {}}) =>
      _ads.pick(widget.placement, formats: AdFormat.slotFormats, exclude: exclude);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _ads.addListener(_onAds);
    _set(_pick());
    _syncTimer();
  }

  @override
  void dispose() {
    _ads.removeListener(_onAds);
    _timer?.cancel();
    super.dispose();
  }

  void _set(AdItem? a) {
    _ad = a;
    _impressed = false;
  }

  /// کانفیگ تازه رسید یا «بدون تبلیغ» فعال شد
  void _onAds() {
    if (!mounted) return;
    final cur = _ad;
    if (cur == null) {
      final n = _pick();
      if (n != null) setState(() => _set(n));
    } else {
      AdItem? fresh;
      for (final x in _ads.config.items) {
        if (x.id == cur.id) fresh = x;
      }
      if (fresh == null || !_ads.gateOpen(widget.placement)) {
        // حذف/غیرفعال شد (یا «بدون تبلیغ» فعال شد) → همین لحظه برداشته می‌شود
        setState(() => _set(_ads.gateOpen(widget.placement) ? _pick() : null));
      } else if (fresh.signature != cur.signature || !fresh.hasPlacement(widget.placement)) {
        // محتوا/جایگاه در پنل ویرایش شد → دوباره انتخاب با داده‌ی جدید
        setState(() => _set(_pick()));
      } else {
        _ad = fresh; // بدون تغییر ظاهری؛ فقط قواعد (فرکانس/هدف‌گیری) به‌روز می‌شود
      }
    }
    _syncTimer();
  }

  void _syncTimer() {
    final sec = _ads.settings.bannerRefreshSec;
    if (sec == _timerSec) return;
    _timerSec = sec;
    _timer?.cancel();
    if (sec > 0) _timer = Timer.periodic(Duration(seconds: sec), (_) => _rotate());
  }

  void _rotate() {
    final cur = _ad;
    if (!mounted || cur == null) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return; // زیر یک شیت/صفحه
    final other = _pick(exclude: {cur.id});
    if (other != null) {
      setState(() => _set(other));
    } else if (_pick() == null) {
      setState(() => _set(null)); // دیگر مجاز نیست (سقف فرکانس و ...)
    }
  }

  void _onShown() {
    final a = _ad;
    if (a == null || _impressed) return;
    _impressed = true;
    _ads.recordImpression(a, widget.placement);
  }

  void _onFailed() {
    final a = _ad;
    if (a == null || !mounted) return;
    _ads.markFailed(a, widget.placement);
    setState(() => _set(_pick(exclude: {a.id})));
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    final s = _ads.settings;

    Widget body = KeyedSubtree(key: ValueKey(ad.id), child: _body(ad));
    body = Padding(padding: widget.padding, child: Center(child: body));

    final canRemove =
        widget.showRemove && s.removeAdsText.isNotEmpty && s.removeAdsUrl.isNotEmpty;
    if (canRemove) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          GestureDetector(
            onTap: () {
              _ads.markExternalLaunch();
              openUrl(s.removeAdsUrl);
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: Text(
                s.removeAdsText,
                style: TextStyle(
                  fontSize: 11.5,
                  color: context.ui.secondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (widget.sticky) {
      body = Material(
        color: context.ui.bg,
        child: SafeArea(top: false, child: body),
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: body,
    );
  }

  Widget _body(AdItem ad) {
    final p = widget.placement;
    if (ad.isNetwork) {
      final adapter = AdNetworks.of(ad.network);
      final unit = _ads.unitIdFor(ad);
      final w = (adapter == null || unit == null)
          ? null
          : adapter.buildInline(
              context,
              ad,
              unit,
              onLoaded: _onShown,
              onFailed: _onFailed,
              onClick: () => _ads.recordClick(ad, p),
            );
      if (w == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _onFailed());
        return const SizedBox.shrink();
      }
      return w;
    }
    final label = adBadge(ad, _ads.settings);
    void tap() => openAd(context, ad, p);
    return switch (ad.format) {
      AdFormat.native => NativeAdCard(ad: ad, label: label, onShown: _onShown, onTap: tap),
      AdFormat.text => TextAdStrip(ad: ad, label: label, onShown: _onShown, onTap: tap),
      AdFormat.html => BannerAdView(
          ad: ad,
          label: label,
          onShown: _onShown,
          onError: _onFailed,
          onTap: tap,
          onLink: (u) {
            _ads.recordClick(ad, p);
            openUrl(u);
          },
        ),
      _ => BannerAdView(
          ad: ad,
          label: label,
          onShown: _onShown,
          onError: _onFailed,
          onTap: tap,
          onLink: (u) {
            _ads.recordClick(ad, p);
            openUrl(u);
          },
        ),
    };
  }
}

// ======================================================================= //
// برچسب «تبلیغ»
// ======================================================================= //
class AdLabelChip extends StatelessWidget {
  final String text;
  final bool onDark;
  const AdLabelChip(this.text, {super.key, this.onDark = true});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: onDark ? Colors.black.withValues(alpha: 0.5) : context.ui.separator,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: onDark ? Colors.white : context.ui.secondary,
          ),
        ),
      );
}

// ======================================================================= //
// بنر (تصویر / ویدیو / HTML)
// ======================================================================= //
class BannerAdView extends StatelessWidget {
  final AdItem ad;
  final String label;
  final VoidCallback onShown;
  final VoidCallback onError;
  final VoidCallback onTap;
  final ValueChanged<String> onLink;

  const BannerAdView({
    super.key,
    required this.ad,
    required this.label,
    required this.onShown,
    required this.onError,
    required this.onTap,
    required this.onLink,
  });

  double get _maxWidth => switch (ad.format) {
        AdFormat.banner || AdFormat.bannerLarge => 360,
        AdFormat.mrec => 300,
        AdFormat.videoBanner => 420,
        _ => 520,
      };

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final Widget media;
    if (ad.isHtml) {
      media = AdHtmlView(html: ad.html, onLink: onLink, onReady: onShown, onError: onError);
    } else if (ad.isVideo) {
      // بنر ویدیویی همیشه بی‌صدا، خودکار و تکرارشونده است
      media = GestureDetector(
        onTap: ad.clickable ? onTap : null,
        child: AdBannerVideo(
          url: ad.mediaUrl,
          posterUrl: ad.posterUrl,
          autoplay: true,
          onReady: onShown,
          onError: onError,
        ),
      );
    } else if (ad.isImage) {
      media = GestureDetector(
        onTap: ad.clickable ? onTap : null,
        child: AdImageView(url: ad.mediaUrl, onReady: onShown, onError: onError),
      );
    } else {
      media = const SizedBox.shrink();
      WidgetsBinding.instance.addPostFrameCallback((_) => onError());
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _maxWidth),
      child: AspectRatio(
        aspectRatio: AdFormat.ratio(ad.format),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ColoredBox(
            color: ui.card,
            child: Stack(
              fit: StackFit.expand,
              children: [
                media,
                PositionedDirectional(
                  top: 6,
                  start: 6,
                  child: IgnorePointer(child: AdLabelChip(label)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================= //
// بومی (Native): کارت هم‌رنگ اپ
// ======================================================================= //
class NativeAdCard extends StatefulWidget {
  final AdItem ad;
  final String label;
  final VoidCallback onShown;
  final VoidCallback onTap;

  /// فشرده (داخل لیست سرورها)
  final bool compact;

  const NativeAdCard({
    super.key,
    required this.ad,
    required this.label,
    required this.onShown,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  @override
  void initState() {
    super.initState();
    // بدون رسانه: همین حالا دیده شده؛ با رسانه: از onReady
    final a = widget.ad;
    if (!(a.isImage || a.isVideo)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onShown();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final ad = widget.ad;
    final bg = ad.backgroundColor ?? ui.card;
    final fg = ad.textColor ?? ui.label;
    final accent = ad.accentColor ?? UiPalette.blue;
    final hasMedia = (ad.isImage || ad.isVideo) && !widget.compact;
    final cta = ad.ctaText.isEmpty ? 'مشاهده' : ad.ctaText;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: ad.clickable ? widget.onTap : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasMedia)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (ad.isVideo)
                        AdBannerVideo(
                          url: ad.mediaUrl,
                          posterUrl: ad.posterUrl,
                          onReady: widget.onShown,
                          onError: () {},
                        )
                      else
                        AdImageView(url: ad.mediaUrl, onReady: widget.onShown),
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: IgnorePointer(child: AdLabelChip(widget.label)),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (ad.iconUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: widget.compact ? 40 : 48,
                          height: widget.compact ? 40 : 48,
                          child: AdImageView(
                            url: ad.iconUrl,
                            onReady: hasMedia ? null : widget.onShown,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (!hasMedia) ...[
                                AdLabelChip(widget.label, onDark: false),
                                const SizedBox(width: 6),
                              ],
                              if (ad.sponsorName.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    ad.sponsorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: 0.55)),
                                  ),
                                ),
                            ],
                          ),
                          if (ad.headline.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                ad.headline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: fg,
                                ),
                              ),
                            ),
                          if (ad.body.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                ad.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, height: 1.5, color: fg.withValues(alpha: 0.7)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (ad.clickable) ...[
                      const SizedBox(width: 10),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: widget.onTap,
                        child: Text(cta, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================================= //
// خط متنی اسپانسر
// ======================================================================= //
class TextAdStrip extends StatefulWidget {
  final AdItem ad;
  final String label;
  final VoidCallback onShown;
  final VoidCallback onTap;
  const TextAdStrip({
    super.key,
    required this.ad,
    required this.label,
    required this.onShown,
    required this.onTap,
  });

  @override
  State<TextAdStrip> createState() => _TextAdStripState();
}

class _TextAdStripState extends State<TextAdStrip> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final ad = widget.ad;
    final bg = ad.backgroundColor ?? ui.card;
    final fg = ad.textColor ?? ui.label;
    final line = [ad.headline, ad.body].where((e) => e.isNotEmpty).join(' — ');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: ad.clickable ? widget.onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                if (ad.iconUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(width: 22, height: 22, child: AdImageView(url: ad.iconUrl)),
                  ),
                  const SizedBox(width: 8),
                ],
                AdLabelChip(widget.label, onDark: false),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: fg, fontWeight: FontWeight.w500),
                  ),
                ),
                if (ad.clickable)
                  Icon(Icons.chevron_left_rounded, color: (ad.accentColor ?? fg.withValues(alpha: 0.5)), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================= //
// آیتم داخل لیست سرورها: «سرور اسپانسری» یا «بومی»
// ======================================================================= //
class InlineAdTile extends StatefulWidget {
  final AdItem ad;
  final String label;
  final VoidCallback onShown;
  final VoidCallback onTap;
  const InlineAdTile({
    super.key,
    required this.ad,
    required this.label,
    required this.onShown,
    required this.onTap,
  });

  @override
  State<InlineAdTile> createState() => _InlineAdTileState();
}

class _InlineAdTileState extends State<InlineAdTile> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    if (ad.format == AdFormat.native) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: NativeAdCard(
          ad: ad,
          label: widget.label,
          onShown: () {}, // شمارش را InlineAdTile انجام می‌دهد
          onTap: widget.onTap,
          compact: true,
        ),
      );
    }
    final ui = context.ui;
    final accent = ad.accentColor ?? UiPalette.blue;
    return ListTile(
      onTap: ad.clickable ? widget.onTap : null,
      tileColor: ad.backgroundColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ad.iconUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 38, height: 38, child: AdImageView(url: ad.iconUrl)),
            )
          : Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(Icons.star_rounded, color: accent, size: 22),
            ),
      title: Text(
        ad.headline.isEmpty ? ad.sponsorName : ad.headline,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, color: ad.textColor ?? ui.label),
      ),
      subtitle: ad.body.isEmpty
          ? null
          : Text(ad.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: (ad.textColor ?? ui.secondary).withValues(alpha: 0.8))),
      trailing: AdLabelChip(widget.label, onDark: false),
    );
  }
}

// ======================================================================= //
// آیکون شناور (مثلاً جعبه‌ی هدیه)
// ======================================================================= //
class FloatingAdIcon extends StatefulWidget {
  const FloatingAdIcon({super.key});

  @override
  State<FloatingAdIcon> createState() => _FloatingAdIconState();
}

class _FloatingAdIconState extends State<FloatingAdIcon> with SingleTickerProviderStateMixin {
  late final _ads = adsOf(context);
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
        ..repeat(reverse: true);
  AdItem? _ad;
  bool _init = false;
  bool _dismissed = false;
  bool _impressed = false;

  AdItem? _pick({Set<int> exclude = const {}}) => _ads.pick(
        AdPlacement.floating,
        formats: const {AdFormat.floatingIcon},
        exclude: exclude,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _ads.addListener(_onAds);
    _ad = _pick();
  }

  void _onAds() {
    if (!mounted || _dismissed) return;
    if (_ad == null) {
      final n = _pick();
      if (n != null) setState(() => _ad = n);
    } else {
      final cur = _ad!;
      AdItem? fresh;
      for (final x in _ads.config.items) {
        if (x.id == cur.id) fresh = x;
      }
      if (fresh == null || !_ads.gateOpen(AdPlacement.floating)) {
        setState(() {
          _ad = _ads.gateOpen(AdPlacement.floating) ? _pick() : null;
          _impressed = false;
        });
      } else if (fresh.signature != cur.signature) {
        setState(() {
          _ad = _pick();
          _impressed = false;
        });
      } else {
        _ad = fresh;
      }
    }
  }

  @override
  void dispose() {
    _ads.removeListener(_onAds);
    _pulse.dispose();
    super.dispose();
  }

  void _shown() {
    final a = _ad;
    if (a == null || _impressed) return;
    _impressed = true;
    _ads.recordImpression(a, AdPlacement.floating);
  }

  void _failed() {
    final a = _ad;
    if (a == null || !mounted) return;
    _ads.markFailed(a, AdPlacement.floating);
    setState(() {
      _ad = _pick(exclude: {a.id});
      _impressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || _dismissed) return const SizedBox.shrink();
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.08).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: SizedBox(
        width: 66,
        height: 66,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 5,
              top: 8,
              child: GestureDetector(
                onTap: ad.clickable ? () => openAd(context, ad, AdPlacement.floating) : null,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: AdImageView(url: ad.mediaUrl, onReady: _shown, onError: _failed),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: () => setState(() => _dismissed = true),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
