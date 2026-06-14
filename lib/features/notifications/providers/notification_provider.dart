import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/notification_model.dart';

/// Ροή ειδοποιήσεων για την οθόνη Ειδοποιήσεων.
final notificationsProvider = StreamProvider<List<NotificationModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(<NotificationModel>[]);

  return FirebaseFirestore.instance
      .collection('notifications')
      .where('targetUid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => NotificationModel.fromFirestore(d)).toList());
});

/// Μετρητής **ξεχωριστών χρηστών** με unread chats για το badge στα Μηνύματα.
/// Αν ένας χρήστης έστειλε 100 μηνύματα, μετράει ως 1.
final unreadCountProvider = StreamProvider<int>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('chats')
      .where('participants', arrayContains: uid)
      .where('unread', isEqualTo: true)
      .snapshots()
      .map((snap) {
    int distinctUsers = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final lastSender = data['lastSenderId'] as String?;
      // Αν δεν ξέρουμε ποιος έστειλε τελευταίος, μετράμε ως unread.
      // Αν είμαστε εμείς οι τελευταίοι αποστολείς, αγνοούμε.
      if (lastSender == null || lastSender != uid) {
        distinctUsers++;
      }
    }
    return distinctUsers;
  });
});

/// Mark όλες τις ειδοποιήσεις του χρήστη ως διαβασμένες.
/// Καλείται από το AppBar action "Όλα διαβασμένα".
Future<void> markAllRead(String uid) async {
  if (uid.isEmpty) return;
  final snap = await FirebaseFirestore.instance
      .collection('notifications')
      .where('targetUid', isEqualTo: uid)
      .where('isRead', isEqualTo: false)
      .get();

  if (snap.docs.isEmpty) return;

  final batch = FirebaseFirestore.instance.batch();
  for (final doc in snap.docs) {
    batch.update(doc.reference, {'isRead': true});
  }
  await batch.commit();
}
