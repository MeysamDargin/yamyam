
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/platform/tv_platform.dart';
import 'package:yamyam/services/app_exception.dart';
import 'package:yamyam/state/app_controller.dart';
import 'package:yamyam/state/app_scope.dart';

/// پرداخت کارت‌به‌کارت و ارسال رسید.
///
/// - [package]: سفارش جدید برای این بسته
/// - [existing]: فقط ارسال/جایگزینی تصویر رسید برای یک سفارش باز
class PaymentPage extends StatefulWidget {
  final GoldPackage? package;
  final PlanOrder? existing;
  const PaymentPage({super.key, this.package, this.existing})
      : assert(package != null || existing != null);

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final _tracking = TextEditingController();
  final _payerName = TextEditingController();
  final _payerCard = TextEditingController();
  final _note = TextEditingController();
  Uint8List? _receipt;
  bool _busy = false;
  String? _error;
  PlanOrder? _done;
  String? _warn;

  @override
  void dispose() {
    _tracking.dispose();
    _payerName.dispose();
    _payerCard.dispose();
    _note.dispose();
    super.dispose();
  }

  String _digits(String s) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      var i = fa.indexOf(ch);
      if (i < 0) i = ar.indexOf(ch);
      b.write(i < 0 ? ch : '$i');
    }
    return b.toString().trim();
  }

  Future<void> _pick(PaymentInfo pay) async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final limit = (pay.maxReceiptMb * 1024 * 1024).round();
      if (bytes.length > limit) {
        setState(() => _error = 'حجم تصویر باید کمتر از ${faDigits(pay.maxReceiptMb)} مگابایت باشد.');
        return;
      }
      setState(() {
        _receipt = bytes;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'انتخاب تصویر ممکن نشد. دسترسی به گالری را بررسی کنید.');
    }
  }

  String? _validate(PaymentInfo pay) {
    if (widget.existing != null) {
      return _receipt == null ? 'یک تصویر برای رسید انتخاب کنید.' : null;
    }
    final tracking = _digits(_tracking.text);
    final hasText = tracking.length >= 4;
    final hasImg = _receipt != null;
    switch (pay.receipt) {
      case 'image':
        if (TvPlatform.isTv) {
          return 'ارسال تصویر رسید روی تلویزیون ممکن نیست. لطفاً از گوشی استفاده کنید.';
        }
        if (!hasImg) return 'تصویر رسید پرداخت را انتخاب کنید.';
      case 'text':
        if (!hasText) return 'کد پیگیری پرداخت را وارد کنید (حداقل ۴ رقم).';
      case 'any':
        if (!hasImg && !hasText) return 'تصویر رسید یا کد پیگیری را وارد کنید.';
    }
    if (pay.requirePayerName && _payerName.text.trim().isEmpty) {
      return 'نام پرداخت‌کننده را وارد کنید.';
    }
    if (pay.requirePayerCard && !RegExp(r'^\d{4}$').hasMatch(_digits(_payerCard.text))) {
      return '۴ رقم آخر کارت پرداخت‌کننده را وارد کنید.';
    }
    return null;
  }

  Future<void> _submit(AppController c) async {
    final pay = c.plans.payment;
    final bad = _validate(pay);
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.existing != null) {
        final o = await c.sendReceipt(widget.existing!, _receipt!);
        if (mounted) setState(() => _done = o);
      } else {
        final r = await c.submitOrder(
          package: widget.package!,
          trackingCode: _digits(_tracking.text),
          payerName: _payerName.text.trim(),
          payerCard: _digits(_payerCard.text),
          note: _note.text.trim(),
          receipt: _receipt,
        );
        if (mounted) {
          setState(() {
            _done = r.order;
            _warn = r.uploadError == null
                ? null
                : 'سفارش ثبت شد اما ارسال تصویر انجام نشد (${r.uploadError}). از صفحه‌ی پلن طلایی دوباره بفرستید.';
          });
        }
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'خطای ناشناخته. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final ui = context.ui;
    final pay = c.plans.payment;
    final accent = parseHexColor(c.plans.gold.accentHex);
    final pkg = widget.package;

    return Scaffold(
      backgroundColor: ui.bg,
      appBar: AppBar(
        backgroundColor: ui.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: ui.label),
        title: Text(
          widget.existing != null ? 'ارسال رسید' : pay.methodTitle,
          style: TextStyle(color: ui.label, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _done != null ? _success(c, accent) : _form(c, pay, accent, pkg),
          ),
        ),
      ),
    );
  }

  Widget _success(AppController c, Color accent) {
    final ui = context.ui;
    final pay = c.plans.payment;
    final o = _done!;
    final approved = o.approved;
    final text = approved
        ? (pay.approvedText.isEmpty ? 'پرداخت تایید شد و پلن طلایی شما فعال است. 🎉' : pay.approvedText)
        : (o.needsReceipt
            ? 'سفارش ثبت شد. برای تکمیل آن، رسید پرداخت را ارسال کنید.'
            : (pay.pendingText.isEmpty
                ? 'رسید شما دریافت شد و در حال بررسی است. نتیجه به‌صورت خودکار در اپ اعلام می‌شود.'
                : pay.pendingText));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(approved ? Icons.verified_rounded : Icons.hourglass_top_rounded,
              size: 72, color: approved ? UiPalette.green : accent),
          const SizedBox(height: 18),
          Text(approved ? 'فعال شد' : 'سفارش ثبت شد',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ui.label)),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: ui.secondary, height: 1.8)),
          if (_warn != null) ...[
            const SizedBox(height: 10),
            Text(_warn!, textAlign: TextAlign.center, style: const TextStyle(color: UiPalette.orange, height: 1.7)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            autofocus: TvPlatform.isTv,
            onPressed: () => Navigator.of(context).pop(),
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4), child: Text('بازگشت')),
          ),
        ],
      ),
    );
  }

  Widget _form(AppController c, PaymentInfo pay, Color accent, GoldPackage? pkg) {
    final ui = context.ui;
    final isNew = widget.existing == null;
    final amount = pkg?.price ?? widget.existing!.amount;
    final title = pkg?.title ?? widget.existing!.packageTitle;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(context),
          child: Row(children: [
            Icon(Icons.workspace_premium_rounded, color: accent, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ui.label)),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoney(amount),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: accent)),
              Text(pay.currency, style: TextStyle(color: ui.secondary, fontSize: 12)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        _cardBox(pay, accent),
        if (pay.instructions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: Text(pay.instructions, style: TextStyle(color: ui.label, height: 1.8, fontSize: 13.5)),
          ),
        ],
        const SizedBox(height: 18),
        if (isNew) ...[
          if (pay.wantsTracking || pay.receipt == 'none')
            _field(_tracking, 'کد پیگیری / شماره مرجع پرداخت${pay.receipt == 'text' ? '' : ' (اختیاری)'}',
                keyboard: TextInputType.number),
          const SizedBox(height: 10),
          _field(_payerName, 'نام پرداخت‌کننده${pay.requirePayerName ? '' : ' (اختیاری)'}'),
          if (pay.requirePayerCard) ...[
            const SizedBox(height: 10),
            _field(_payerCard, '۴ رقم آخر کارت پرداخت‌کننده',
                keyboard: TextInputType.number, maxLength: 4),
          ],
          const SizedBox(height: 10),
          _field(_note, 'توضیحات (اختیاری)', lines: 2),
          const SizedBox(height: 14),
        ],
        if (pay.wantsImage || !isNew) _receiptPicker(pay, accent),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: UiPalette.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: UiPalette.red, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(_error!, style: const TextStyle(color: UiPalette.red, height: 1.5, fontSize: 13))),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF2B1F00),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              textStyle: const TextStyle(fontFamily: kAppFont, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            onPressed: _busy ? null : () => _submit(c),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                : Text(isNew ? 'ثبت پرداخت و ارسال' : 'ارسال رسید'),
          ),
        ),
        if (isNew)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              TvPlatform.isTv
                  ? 'توجه: پلن طلایی مخصوص همین تلویزیون فعال می‌شود.'
                  : 'پلن طلایی برای همین دستگاه فعال می‌شود.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ui.secondary, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Widget _field(TextEditingController ctl, String label,
      {TextInputType? keyboard, int lines = 1, int? maxLength}) {
    final ui = context.ui;
    return TextField(
      controller: ctl,
      keyboardType: keyboard,
      minLines: lines,
      maxLines: lines,
      maxLength: maxLength,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      style: TextStyle(color: ui.label),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        filled: true,
        fillColor: ui.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _receiptPicker(PaymentInfo pay, Color accent) {
    final ui = context.ui;
    if (TvPlatform.isTv) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: ui.card, borderRadius: BorderRadius.circular(16)),
        child: Text(
          pay.receipt == 'image'
              ? 'ارسال تصویر رسید روی تلویزیون ممکن نیست؛ برای این روش پرداخت از گوشی استفاده کنید.'
              : 'روی تلویزیون فقط کد پیگیری ارسال می‌شود.',
          style: TextStyle(color: ui.secondary, height: 1.7, fontSize: 13),
        ),
      );
    }
    final required = pay.receipt == 'image' || widget.existing != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: ui.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تصویر رسید${required ? '' : ' (اختیاری اگر کد پیگیری را وارد کرده‌اید)'}',
              style: TextStyle(fontWeight: FontWeight.w700, color: ui.label)),
          const SizedBox(height: 10),
          if (_receipt != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Image.memory(_receipt!, fit: BoxFit.contain, width: double.infinity),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pick(pay),
            icon: const Icon(Icons.image_rounded),
            label: Text(_receipt == null ? 'انتخاب تصویر از گالری' : 'تغییر تصویر'),
          ),
        ],
      ),
    );
  }

  Widget _cardBox(PaymentInfo pay, Color accent) {
    final dark = Color.lerp(accent, Colors.black, 0.45)!;
    final number = pay.cardNumberPretty.isNotEmpty ? pay.cardNumberPretty : pay.cardNumber;

    Widget copyRow(String label, String value, {bool ltr = false}) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(value,
                  textDirection: ltr ? TextDirection.ltr : null,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: [dark, Color.lerp(accent, Colors.black, 0.15)!]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.credit_card_rounded, color: Colors.white70),
            const SizedBox(width: 8),
            Text(pay.bankName.isEmpty ? 'شماره کارت' : pay.bankName,
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(number,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
              IconButton(
                tooltip: 'کپی',
                autofocus: TvPlatform.isTv,
                icon: const Icon(Icons.copy_rounded, color: Colors.white),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: pay.cardNumber));
                  _snack('شماره کارت کپی شد');
                },
              ),
            ]),
          ),
          if (pay.cardHolder.isNotEmpty) copyRow('به نام', pay.cardHolder),
          if (pay.sheba.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Text('شبا', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(pay.sheba,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pay.sheba));
                    _snack('شماره شبا کپی شد');
                  },
                ),
              ]),
            ),
          const SizedBox(height: 6),
          Text('مبلغ را دقیقاً به همین کارت واریز کنید، سپس رسید را ثبت کنید.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, height: 1.6)),
        ],
      ),
    );
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
}
