/// کش دیسکیِ رسانه‌ی تبلیغات.
///
/// هر فایل فقط یک‌بار دانلود می‌شود (برای نمایش‌های بعدی هیچ مصرف اینترنتی ندارد)،
/// روی اینترنت همراه سقف حجم دارد و دانلودهای هم‌زمانِ یک آدرس ادغام می‌شوند.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MediaCache {
  MediaCache({http.Client? client, Directory? dir})
      : _client = client ?? http.Client(),
        _dir = dir;

  final http.Client _client;
  Directory? _dir;
  final Set<String> _names = {};
  final Map<String, Future<File?>> _inflight = {};

  /// سقف مطلق هر فایل (هم‌سو با سقف آپلود پنل)
  static const hardMaxBytes = 90 * 1024 * 1024;

  Future<void> init() async {
    _dir ??= Directory('${(await getTemporaryDirectory()).path}/ads_media');
    final d = _dir!;
    if (!await d.exists()) await d.create(recursive: true);
    _names.clear();
    await for (final e in d.list()) {
      if (e is File) {
        final n = e.uri.pathSegments.last;
        if (n.endsWith('.part')) {
          unawaited(e.delete().catchError((_) => e));
        } else {
          _names.add(n);
        }
      }
    }
  }

  /// FNV-1a 64 (ثابت بین اجراها، برخلاف hashCode)
  @visibleForTesting
  static String nameFor(String url) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final b in url.codeUnits) {
      h = ((h ^ BigInt.from(b & 0xff)) * prime) & mask;
    }
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final dot = path.lastIndexOf('.');
    var ext = dot >= 0 ? path.substring(dot) : '';
    if (!RegExp(r'^\.[a-z0-9]{2,5}$').hasMatch(ext)) ext = '.bin';
    return '${h.toRadixString(16).padLeft(16, '0')}$ext';
  }

  bool has(String url) => url.isNotEmpty && _names.contains(nameFor(url));

  File? file(String url) {
    final d = _dir;
    if (d == null || !has(url)) return null;
    return File('${d.path}/${nameFor(url)}');
  }

  /// فایل را (اگر لازم بود دانلود و) برمی‌گرداند. null = ناموفق یا بیش از [maxBytes].
  Future<File?> ensure(String url, {int? maxBytes}) {
    if (url.isEmpty) return Future.value(null);
    final cached = file(url);
    if (cached != null) return Future.value(cached);
    // نکته: whenComplete اگر Future برگردانَد منتظرش می‌ماند (remove خودِ همین Future را
    // برمی‌گرداند → قفل). به همین دلیل بدنه‌ی بلوکی است.
    return _inflight[url] ??= _download(url, maxBytes ?? hardMaxBytes).whenComplete(() {
      _inflight.remove(url);
    });
  }

  Future<File?> _download(String url, int maxBytes) async {
    final dir = _dir;
    final uri = Uri.tryParse(url);
    if (dir == null || uri == null || !uri.hasScheme) return null;
    final name = nameFor(url);
    final part = File('${dir.path}/$name.part');
    IOSink? sink;
    try {
      final res = await _client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final declared = res.contentLength;
      if (declared != null && declared > maxBytes) return null;

      final w = part.openWrite();
      sink = w;
      var n = 0;
      await for (final chunk in res.stream.timeout(const Duration(seconds: 20))) {
        n += chunk.length;
        if (n > maxBytes) {
          sink = null;
          await w.close();
          await part.delete();
          return null;
        }
        w.add(chunk);
      }
      sink = null;
      await w.flush();
      await w.close();
      if (n == 0) {
        await part.delete();
        return null;
      }
      final out = await part.rename('${dir.path}/$name');
      _names.add(name);
      return out;
    } catch (e) {
      debugPrint('ad media download failed: $e');
      try {
        await sink?.close();
        if (await part.exists()) await part.delete();
      } catch (_) {}
      return null;
    }
  }

  /// فایل‌هایی که دیگر در کانفیگ نیستند حذف می‌شوند؛ سپس کل حجم زیر [maxTotalBytes] نگه داشته می‌شود.
  Future<void> prune(Set<String> keepUrls, {int maxTotalBytes = 200 * 1024 * 1024}) async {
    final d = _dir;
    if (d == null) return;
    final keep = {for (final u in keepUrls) nameFor(u)};
    final files = <File>[];
    await for (final e in d.list()) {
      if (e is! File) continue;
      final n = e.uri.pathSegments.last;
      if (n.endsWith('.part')) continue;
      if (!keep.contains(n)) {
        try {
          await e.delete();
          _names.remove(n);
        } catch (_) {}
      } else {
        files.add(e);
      }
    }
    var total = 0;
    for (final f in files) {
      total += await f.length();
    }
    if (total <= maxTotalBytes) return;
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    for (final f in files) {
      if (total <= maxTotalBytes) break;
      total -= await f.length();
      try {
        await f.delete();
        _names.remove(f.uri.pathSegments.last);
      } catch (_) {}
    }
  }

  void dispose() => _client.close();
}
