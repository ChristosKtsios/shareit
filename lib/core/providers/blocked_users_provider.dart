import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';

/// Τα UIDs που έχει μπλοκάρει ο τρέχων χρήστης.
///
/// Το `blockedUids` διαβαζόταν ΜΟΝΟ στο chat/inbox. Αυτό σήμαινε ότι μπλοκάρεις
/// κάποιον και συνεχίζεις να βλέπεις τις αγγελίες του στο feed, στην αναζήτηση
/// και στον χάρτη — το μπλοκάρισμα έμοιαζε σπασμένο, και η πολιτική UGC του
/// Play περιμένει να είναι πραγματικά αποτελεσματικό πάνω στο περιεχόμενο, όχι
/// μόνο στα μηνύματα.
final blockedUidsProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(const <String>{});
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => Set<String>.from(
          (doc.data()?['blockedUids'] as List<dynamic>?) ?? const []))
      // Offline / permission-denied → μην ρίξεις την οθόνη· απλώς μη φιλτράρεις.
      .handleError((_) {});
});

/// Το ίδιο, σε μορφή έτοιμη για χρήση μέσα σε build: άδειο σύνολο όσο φορτώνει
/// ή αν αποτύχει, ώστε το περιεχόμενο να μη «χαθεί» κατά λάθος.
extension BlockedUidsRead on WidgetRef {
  Set<String> get blockedUids =>
      watch(blockedUidsProvider).valueOrNull ?? const <String>{};
}
