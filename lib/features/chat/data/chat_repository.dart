import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRepository {
  final _db = FirebaseFirestore.instance;

  Future<String> getOrCreate({
    required String currentUid, required String otherUid,
    required String listingId, required String listingTitle,
    required String otherUserName,
  }) async {
    final ex = await _db.collection('chats')
        .where('listingId', isEqualTo: listingId)
        .where('participants', arrayContains: currentUid).limit(1).get();
    if (ex.docs.isNotEmpty) return ex.docs.first.id;
    final doc = await _db.collection('chats').add({
      'listingId': listingId, 'listingTitle': listingTitle,
      'participants': [currentUid, otherUid],
      'otherUserName': otherUserName,
      'lastMessage': '', 'lastMessageAt': FieldValue.serverTimestamp(), 'unread': false,
    });
    return doc.id;
  }

  Future<void> send({required String chatId, required String senderId, required String text}) async {
    final batch = _db.batch();
    batch.set(_db.collection('chats').doc(chatId).collection('messages').doc(),
        {'text': text, 'senderId': senderId, 'sentAt': FieldValue.serverTimestamp()});
    batch.update(_db.collection('chats').doc(chatId),
        {'lastMessage': text, 'lastMessageAt': FieldValue.serverTimestamp(), 'unread': true});
    await batch.commit();
  }

  Stream<QuerySnapshot> messagesStream(String chatId) =>
      _db.collection('chats').doc(chatId).collection('messages')
          .orderBy('sentAt').snapshots();

  Stream<QuerySnapshot> inboxStream(String uid) =>
      _db.collection('chats').where('participants', arrayContains: uid)
          .orderBy('lastMessageAt', descending: true).snapshots();

  Future<void> markRead(String chatId) =>
      _db.collection('chats').doc(chatId).update({'unread': false});
}
