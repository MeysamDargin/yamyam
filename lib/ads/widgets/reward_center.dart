import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yamyam/ads/ad_flow.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/state/app_controller.dart';

/// ردیف «ویدیو ببین، جایزه بگیر» (مرکز جایزه). اگر تبلیغ پاداش‌داری در دسترس نباشد
/// هیچ چیزی نشان داده نمی‌شود.
class RewardCenterRow extends StatelessWidget {
  final AppController controller;

  /// بالای ردیف یک جداکننده‌ی نازک بگذار (داخل کارت)
  final bool divider;
  const RewardCenterRow({super.key, required this.controller, this.divider = true});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: c.ads,
      builder: (context, _) {
        if (!AdFlow.rewardAvailable(c)) return const SizedBox.shrink();
        final ui = context.ui;
        final coins = c.ads.ledger.coins;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (divider)
              Divider(height: 1, thickness: 0.5, indent: 16, endIndent: 16, color: ui.separator),
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                AdFlow.watchForReward(context, c);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: UiPalette.amber.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.card_giftcard_rounded, color: UiPalette.amber, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ویدیو ببین، جایزه بگیر',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: ui.label,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            coins > 0
                                ? 'موجودی سکه‌ی شما: ${faDigits(coins)}'
                                : 'یک ویدیوی کوتاه ببینید و هدیه بگیرید',
                            style: TextStyle(fontSize: 12.5, color: ui.secondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_left_rounded, color: ui.secondary.withValues(alpha: 0.8)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
