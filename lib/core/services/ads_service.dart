import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob ad unit IDs. Σε debug χρησιμοποιούμε τα επίσημα Google test IDs ώστε
/// να μη ρισκάρουμε invalid-traffic policy strike ή να σπαταλάμε πραγματικές
/// εμφανίσεις κατά την ανάπτυξη.
class AdsService {
  AdsService._();

  static String get bannerAdUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-2901037704059388/9201872012';

  static String get rewardedAdUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-2901037704059388/1702655947';

  /// Ζητά GDPR consent (Google UMP) πριν αρχικοποιήσει το SDK — υποχρεωτικό
  /// για χρήστες στον ΕΟΧ/Ην. Βασίλειο/Ελβετία. Εκτός αυτών των περιοχών το
  /// UMP δεν δείχνει καν φόρμα, οπότε προχωράμε κατευθείαν.
  static Future<void> initialize() async {
    final completer = Completer<void>();

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((_) async {
          await MobileAds.instance.initialize();
          if (!completer.isCompleted) completer.complete();
        });
      },
      (_) async {
        // Αποτυχία λήψης consent status (π.χ. offline) — αρχικοποιούμε ούτως
        // ή άλλως, το SDK θα δείξει non-personalized ads by default.
        await MobileAds.instance.initialize();
        if (!completer.isCompleted) completer.complete();
      },
    );

    // Αν το δίκτυο «κολλήσει» ακριβώς τη στιγμή του consent request (π.χ.
    // στιγμιαία διακοπή σύνδεσης στην εκκίνηση), το requestConsentInfoUpdate
    // μπορεί να μην καλέσει ΚΑΝΕΝΑ από τα δύο callbacks — χωρίς timeout το
    // SDK δεν αρχικοποιείται ΠΟΤΕ για όλη τη διάρκεια της συνεδρίας, και
    // καμία διαφήμιση δεν φορτώνει ξανά μέχρι να ξανανοίξει η εφαρμογή.
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => MobileAds.instance.initialize(),
    );
  }

  /// Φορτώνει και δείχνει ένα rewarded ad. Καλεί το [onEarnedReward] ΜΟΝΟ αν
  /// ο χρήστης είδε τη διαφήμιση μέχρι το τέλος (AdMob reward callback), και
  /// [onFailed] αν δεν υπήρχε διαθέσιμη διαφήμιση ή απέτυχε η εμφάνιση.
  ///
  /// ΣΗΜΕΙΩΣΗ ασφάλειας: δεν γίνεται server-side verification (AdMob SSV) του
  /// reward callback — ένας client που παρακάμπτει το UI θα μπορούσε να
  /// καλέσει απευθείας το [ListingRepository.boost]. Το firestore.rules
  /// βάζει πλαφόν στο boostTimestamps (μία πρόσφατη χρονοσφραγίδα ανά write),
  /// και η ζημιά ενός ψεύτικου boost στη ΔΙΚΗ του αγγελία είναι αμελητέα —
  /// αποδεκτό ρίσκο για αυτό το feature.
  static void showRewarded({
    required VoidCallback onEarnedReward,
    required VoidCallback onFailed,
  }) {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          );
          ad.show(onUserEarnedReward: (_, __) => onEarnedReward());
        },
        onAdFailedToLoad: (error) => onFailed(),
      ),
    );
  }
}
