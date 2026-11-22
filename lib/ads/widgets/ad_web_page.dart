import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/widgets/open_url.dart';

/// صفحه‌ی داخل‌اپی برای «باز کردن داخل اپ (WebView)». فقط http/https باز می‌شود؛
/// لینک‌های اپ‌های دیگر (tg://, market://, ...) بیرون از اپ باز می‌شوند.
class AdWebPage extends StatefulWidget {
  final String url;
  final String title;
  const AdWebPage({super.key, required this.url, this.title = ''});

  @override
  State<AdWebPage> createState() => _AdWebPageState();
}

class _AdWebPageState extends State<AdWebPage> {
  late final WebViewController _wc;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onNavigationRequest: (r) {
          final scheme = Uri.tryParse(r.url)?.scheme ?? '';
          if (scheme == 'http' || scheme == 'https' || r.url == 'about:blank') {
            return NavigationDecision.navigate;
          }
          openUrl(r.url);
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return Scaffold(
      backgroundColor: ui.bg,
      appBar: AppBar(
        backgroundColor: ui.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.title.isEmpty ? (Uri.tryParse(widget.url)?.host ?? '') : widget.title,
          style: TextStyle(fontSize: 15, color: ui.label),
        ),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100, minHeight: 2),
              )
            : null,
      ),
      body: WebViewWidget(controller: _wc),
    );
  }
}
