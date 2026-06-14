import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRepository {
  final _db = FirebaseFirestore.instance;

  Future<String> getOrCreate({
    required String currentUid,
    required String otherUid,
    required String listingId,
    required String listingTitle,
    required String otherUserName,
  }) async {
    // Ψάχνει υπάρχον chat ΜΕ ΤΟΝ ΣΥΓΚΕΚΡΙΜΕΝΟ ΧΡΗΣΤΗ (όχι ανά αγγελία).
    // Όλες οι αγγελίες με τον ίδιο χρήστη → ένα chat (σαν Messenger).
    final ex = await _db
        .collection('chats')
        .where('participants', arrayContains: currentUid)
        .get();
    for (final doc in ex.docs) {
      final participants = List<String>.from(doc.data()['participants'] ?? []);
      if (participants.contains(otherUid) && participants.length == 2) {
        return doc.id;
      }
    }

    final doc = await _db.collection('chats').add({
      'listingId': listingId,
      'listingTitle': listingTitle,
      'participants': [currentUid, otherUid],
      'otherUserName': otherUserName,
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': null,
      'unread': false,
    });
    return doc.id;
  }

  Future<void> send({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final batch = _db.batch();
    batch.set(
      _db.collection('chats').doc(chatId).collection('messages').doc(),
      {
        'text': text,
        'senderId': senderId,
        'sentAt': FieldValue.serverTimestamp(),
        'messageType': 'text',
      },
    );
    batch.update(_db.collection('chats').doc(chatId), {
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': senderId,
      'unread': true,
    });
    await batch.commit();
  }

  Future<void> sendDealProposalMessage({
    required String chatId,
    required String senderId,
    required String dealId,
    required String title,
    required String description,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final batch = _db.batch();
    batch.set(
      _db.collection('chats').doc(chatId).collection('messages').doc(),
      {
        'text': '📋 Πρόταση Deal: $title',
        'senderId': senderId,
        'sentAt': FieldValue.serverTimestamp(),
        'messageType': 'deal_proposal',
        'dealData': {
          'dealId': dealId,
          'title': title,
          'description': description,
          'startDate': Timestamp.fromDate(startDate),
          'endDate': Timestamp.fromDate(endDate),
        },
      },
    );
    batch.update(_db.collection('chats').doc(chatId), {
      'lastMessage': '📋 Πρόταση Deal',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': senderId,
      'unread': true,
    });
    await batch.commit();
  }


  Future<void> sendMediaMessage({
    required String chatId,
    required String senderId,
    required String mediaUrl,
    required String mediaType,
  }) async {
    final preview = mediaType == 'image' ? '📷 Φωτογραφία' : '🎥 Βίντεο';
    final batch = _db.batch();
    batch.set(
      _db.collection('chats').doc(chatId).collection('messages').doc(),
      {
        'text': preview,
        'senderId': senderId,
        'sentAt': FieldValue.serverTimestamp(),
        'messageType': mediaType,
        'mediaUrl': mediaUrl,
      },
    );
    batch.update(_db.collection('chats').doc(chatId), {
      'lastMessage': preview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': senderId,
      'unread': true,
    });
    await batch.commit();
  }

  Stream<QuerySnapshot> messagesStream(String chatId) => _db
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .orderBy('sentAt')
      .snapshots();

  Stream<QuerySnapshot> inboxStream(String uid) => _db
      .collection('chats')
      .where('participants', arrayContains: uid)
      .orderBy('lastMessageAt', descending: true)
      .snapshots();

  /// Inbox stream που φιλτράρει chats με blocked users.
  /// Επιστρέφει τα chats όπου ΟΥΤΕ συμμετέχει blocked user
  /// ΟΥΤΕ ο current user έχει μπλοκαριστεί από τον άλλο.
  Stream<List<QueryDocumentSnapshot>> inboxStreamFiltered(String uid) async* {
    // 1) Πάρε τη λίστα blocked του current user
    final userDoc = await _db.collection('users').doc(uid).get();
    final myBlocked = List<String>.from(userDoc.data()?['blockedUids'] ?? []);

    // 2) Stream όλα τα chats του user
    final stream = _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();

    await for (final snap in stream) {
      final filtered = <QueryDocumentSnapshot>[];
      for (final doc in snap.docs) {
        final participants = List<String>.from(doc.data()['participants'] ?? []);
        final otherUid = participants.firstWhere((p) => p != uid, orElse: () => '');
        if (otherUid.isEmpty) continue;

        // Φίλτρο 1: Είναι αυτός μπλοκαρισμένος από εμένα;
        if (myBlocked.contains(otherUid)) continue;

        // Φίλτρο 2: Έχει ο άλλος μπλοκάρει εμένα;
        final otherDoc = await _db.collection('users').doc(otherUid).get();
        final otherBlocked = List<String>.from(otherDoc.data()?['blockedUids'] ?? []);
        if (otherBlocked.contains(uid)) continue;

        filtered.add(doc);
      }
      yield filtered;
    }
  }

  Future<void> markRead(String chatId) =>
      _db.collection('chats').doc(chatId).update({'unread': false});

  Future<void> deleteMessage(String chatId, String messageId) =>
      _db.collection('chats').doc(chatId).collection('messages')
          .doc(messageId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'text': '',
      });
}
