import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yamyam/ads/ads_manager.dart';
import 'package:yamyam/state/app_scope.dart';

AdsManager adsOf(BuildContext context) => AppScope.of(context, listen: false).ads;

// ======================================================================= //
// تصویر (از کش دیسک؛ در صورت نبودن با رعایت سقف حجم دانلود می‌شود)
// ======================================================================= //
class AdImageView extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  final Widget? placeholder;

  const AdImageView({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.onReady,
    this.onError,
    this.placeholder,
  });

  @override
  State<AdImageView> createState() => _AdImageViewState();
}

class _AdImageViewState extends State<AdImageView> {
  Future<File?> _file = Future<File?>.value(null);
  bool _started = false;
  bool _reported = false;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final ads = adsOf(context);
    _file = ads.loadMedia(widget.url).then((f) {
      if (f == null && mounted) {
        _failed = true;
        widget.onError?.call();
      }
      return f;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _file,
      builder: (_, snap) {
        final f = snap.data;
        if (f == null) {
          return _failed ? const SizedBox.shrink() : (widget.placeholder ?? const SizedBox.shrink());
        }
        return Image.file(
          f,
          fit: widget.fit,
          gaplessPlayback: true,
          width: double.infinity,
          height: double.infinity,
          frameBuilder: (_, child, frame, sync) {
            if ((frame != null || sync) && !_reported) {
              _reported = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.onReady?.call();
              });
            }
            return child;
          },
          errorBuilder: (_, __, ___) {
            if (!_failed) {
              _failed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.onError?.call();
              });
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

// ======================================================================= //
// ویدیو
// ======================================================================= //
/// ویدیو را اول در کش ذخیره می‌کند (بازپخش رایگان) و از فایل محلی پخش می‌کند.
Future<VideoPlayerController?> openAdVideo(
  AdsManager ads,
  String url, {
  bool muted = true,
  bool loop = false,
}) async {
  final f = await ads.loadMedia(url);
  if (f == null) return null;
  final c = VideoPlayerController.file(
    f,
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );
  try {
    await c.initialize();
    await c.setVolume(muted ? 0 : 1);
    await c.setLooping(loop);
    return c;
  } catch (_) {
    await c.dispose();
    return null;
  }
}

/// نمایش یک [VideoPlayerController] آماده، پر کردن قاب
class AdVideoSurface extends StatelessWidget {
  final VideoPlayerController controller;
  final bool cover;
  const AdVideoSurface({super.key, required this.controller, this.cover = true});

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (size.isEmpty) return const SizedBox.shrink();
    return ClipRect(
      child: FittedBox(
        fit: cover ? BoxFit.cover : BoxFit.contain,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

/// ویدیوی بنری: بی‌صدا، خودکار، تکرارشونده؛ با رفتن اپ به پس‌زمینه متوقف می‌شود.
class AdBannerVideo extends StatefulWidget {
  final String url;
  final String posterUrl;
  final bool autoplay;
  final VoidCallback? onReady;
  final VoidCallback? onError;

  const AdBannerVideo({
    super.key,
    required this.url,
    this.posterUrl = '',
    this.autoplay = true,
    this.onReady,
    this.onError,
  });

  @override
  State<AdBannerVideo> createState() => _AdBannerVideoState();
}

class _AdBannerVideoState extends State<AdBannerVideo> with WidgetsBindingObserver {
  VideoPlayerController? _c;
  bool _started = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    openAdVideo(adsOf(context), widget.url, muted: true, loop: true).then((c) {
      if (c == null) {
        if (mounted) widget.onError?.call();
        return;
      }
      if (_disposed) {
        c.dispose();
        return;
      }
      setState(() => _c = c);
      if (widget.autoplay) c.play();
      widget.onReady?.call();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null) return;
    if (state == AppLifecycleState.resumed) {
      if (widget.autoplay) c.play();
    } else {
      c.pause();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (c == null && widget.posterUrl.isNotEmpty)
          AdImageView(url: widget.posterUrl),
        if (c != null) AdVideoSurface(controller: c),
      ],
    );
  }
}

// ======================================================================= //
// HTML (WebView ایزوله؛ لینک‌ها بیرون از WebView باز می‌شوند)
// ======================================================================= //
class AdHtmlView extends StatefulWidget {
  final String html;
  final ValueChanged<String> onLink;
  final VoidCallback? onReady;
  final VoidCallback? onError;

  const AdHtmlView({
    super.key,
    required this.html,
    required this.onLink,
    this.onReady,
    this.onError,
  });

  @override
  State<AdHtmlView> createState() => _AdHtmlViewState();
}

class _AdHtmlViewState extends State<AdHtmlView> {
  late final WebViewController _wc;
  bool _ready = false;

  static String wrap(String body) => '<!doctype html><html><head>'
      '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">'
      '<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}'
      'img,video{max-width:100%}</style></head><body>$body</body></html>';

  @override
  void initState() {
    super.initState();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          final u = r.url;
          if (!r.isMainFrame || u == 'about:blank' || u.startsWith('data:')) {
            return NavigationDecision.navigate;
          }
          widget.onLink(u);
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          if (_ready) return;
          _ready = true;
          widget.onReady?.call();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) widget.onError?.call();
        },
      ))
      ..loadHtmlString(wrap(widget.html));
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _wc);
}
