import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notification_model.dart';
import '../../auth/providers/auth_provider.dart';

final _db = FirebaseFirestore.instance;

final notificationsProvider = StreamProvider<List<NotificationModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream<List<NotificationModel>>.empty();
  return _db.collection('notifications')
      .where('targetUid', isEqualTo: uid)
      .orderBy('createdAt', descending: true).limit(50)
      .snapshots()
      .map((s) => s.docs.map(NotificationModel.fromFirestore).toList());
});

final unreadCountProvider = Provider<int>((ref) =>
    ref.watch(notificationsProvider)
        .whenData((l) => l.where((n) => !n.isRead).length)
        .valueOrNull ?? 0);

Future<void> markAllRead(String uid) async {
  final batch = _db.batch();
  final snap = await _db.collection('notifications')
      .where('targetUid', isEqualTo: uid).where('isRead', isEqualTo: false).get();
  for (final doc in snap.docs) {
    batch.update(doc.reference, {'isRead': true});
  }
  await batch.commit();
}
