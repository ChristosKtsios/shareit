import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';

/// Προειδοποιήσεις ασφαλείας κατά της απάτης.
///
/// Γιατί υπάρχει: η εφαρμογή φέρνει σε επαφή αγνώστους για συναλλαγές εκτός
/// πλατφόρμας. Οι όροι χρήσης λένε «δεν φέρουμε ευθύνη» — αλλά μια αποποίηση
/// ευθύνης δεν προστατεύει ούτε τον χρήστη ούτε, στην πράξη, εμάς. Αυτό που
/// μετράει είναι να **προειδοποιείται** ο χρήστης τη στιγμή που κινδυνεύει:
/// μέσα στη συνομιλία και τη στιγμή που κλείνει deal.
class SafetyTips {
  SafetyTips._();

  static const _dismissedKey = 'safety_tips_chat_dismissed';

  static Future<bool> chatBannerDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dismissedKey) ?? false;
  }

  static Future<void> dismissChatBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, true);
  }

  static const _tipKeys = [
    'safety.tipPublicPlace',
    'safety.tipNoPrepay',
    'safety.tipInspect',
    'safety.tipNoBankDetails',
    'safety.tipTooGood',
    'safety.tipReport',
  ];

  /// Συμπαγής κάρτα προειδοποίησης — για την οθόνη πρότασης deal, όπου ο
  /// κίνδυνος είναι μεγαλύτερος. Εμφανίζεται ΠΑΝΤΑ (δεν κρύβεται).
  static Widget card() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.35), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.shield_outlined,
                  color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('safety.title'.tr(),
                    style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            ..._tipKeys.map((k) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12.5)),
                      Expanded(
                        child: Text(k.tr(),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                                height: 1.35)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      );

  /// Banner στη συνομιλία — απορρίπτεται μία φορά και δεν ξαναεμφανίζεται.
  static Widget chatBanner({required VoidCallback onDismiss}) => Container(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.shield_outlined,
              color: AppColors.warning, size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('safety.title'.tr(),
                    style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('safety.chatShort'.tr(),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35)),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.close,
                size: 16, color: AppColors.textHint),
            onPressed: onDismiss,
          ),
        ]),
      );
}
