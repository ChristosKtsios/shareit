import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Καταγράφει non-fatal σφάλματα που αλλιώς θα «καταπίνονταν» σιωπηλά, ώστε να
/// είναι ορατά στο Crashlytics (production) και στο console (debug) — χωρίς να
/// μπλοκάρουν τη ροή. Χρησιμοποιείται σε catch blocks για operations όπου η
/// αποτυχία δεν πρέπει να σταματά τον χρήστη, αλλά θέλουμε να τη βλέπουμε.
void logSwallowed(Object error, [StackTrace? stack, String? reason]) {
  if (kDebugMode) {
    debugPrint('⚠️ swallowed${reason != null ? ' [$reason]' : ''}: $error');
  }
  FirebaseCrashlytics.instance
      .recordError(error, stack, reason: reason, fatal: false);
}
