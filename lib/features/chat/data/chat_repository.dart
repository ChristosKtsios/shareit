import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/error_logger.dart';

class ChatRepository {
  final _db = FirebaseFirestore.instance;

  Future<String> getOrCreate({
    required String currentUid,
    required String otherUid,
    required String listingId,
    required String listingTitle,
    required String otherUserName,
  }) async {
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
    Map<String, dynamic>? replyTo,
  }) async {
    // 1. Πρώτα δημιούργησε το message
    await _db.collection('chats').doc(chatId).collection('messages').add({
      'text': text,
      'senderId': senderId,
      'sentAt': FieldValue.serverTimestamp(),
      'messageType': 'text',
      if (replyTo != null) 'replyTo': replyTo,
    });
    // 2. Μετά update το chat doc (αν αποτύχει, το μήνυμα έχει σταλεί ήδη)
    try {
      await _db.collection('chats').doc(chatId).update({
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': senderId,
        'unread': true,
      });
    } catch (e, s) {
      logSwallowed(e, s, 'chat lastMessage update');
    }
  }

  /// Στέλνει typed «deal closed» μήνυμα (σύστημα). Δεν αποθηκεύει ελληνικό
  /// κείμενο — το bubble το εμφανίζει localized με βάση το `dealClosedDays`.
  Future<void> sendDealClosedMessage({
    required String chatId,
    required String senderId,
    required int durationDays,
  }) async {
    await _db.collection('chats').doc(chatId).collection('messages').add({
      'text': '',
      'senderId': senderId,
      'sentAt': FieldValue.serverTimestamp(),
      'messageType': 'deal_closed',
      'dealClosedDays': durationDays,
    });
    try {
      await _db.collection('chats').doc(chatId).update({
        'lastMessage': '🤝 deal_closed',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': senderId,
        'unread': true,
      });
    } catch (e, s) {
      logSwallowed(e, s, 'chat lastMessage update');
    }
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
    await _db.collection('chats').doc(chatId).collection('messages').add({
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
    });
    try {
      await _db.collection('chats').doc(chatId).update({
        'lastMessage': '📋 Πρόταση Deal',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': senderId,
        'unread': true,
      });
    } catch (e, s) {
      logSwallowed(e, s, 'chat lastMessage update');
    }
  }

  Future<void> sendMediaMessage({
    required String chatId,
    required String senderId,
    required String mediaUrl,
    required String mediaType,
    Map<String, dynamic>? replyTo,
  }) async {
    final preview = mediaType == 'image' ? '📷 Φωτογραφία' : '🎥 Βίντεο';
    await _db.collection('chats').doc(chatId).collection('messages').add({
      'text': preview,
      'senderId': senderId,
      'sentAt': FieldValue.serverTimestamp(),
      'messageType': mediaType,
      'mediaUrl': mediaUrl,
      if (replyTo != null) 'replyTo': replyTo,
    });
    try {
      await _db.collection('chats').doc(chatId).update({
        'lastMessage': preview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': senderId,
        'unread': true,
      });
    } catch (e, s) {
      logSwallowed(e, s, 'chat lastMessage update');
    }
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

  Stream<List<QueryDocumentSnapshot>> inboxStreamFiltered(String uid) async* {
    final userDoc = await _db.collection('users').doc(uid).get();
    final myBlocked = List<String>.from(userDoc.data()?['blockedUids'] ?? []);

    final stream = _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();

    await for (final snap in stream) {
      final filtered = <QueryDocumentSnapshot>[];
      for (final doc in snap.docs) {
        final participants =
            List<String>.from(doc.data()['participants'] ?? []);
        final otherUid =
            participants.firstWhere((p) => p != uid, orElse: () => '');
        if (otherUid.isEmpty) continue;
        if (myBlocked.contains(otherUid)) continue;
        final otherDoc = await _db.collection('users').doc(otherUid).get();
        final otherBlocked =
            List<String>.from(otherDoc.data()?['blockedUids'] ?? []);
        if (otherBlocked.contains(uid)) continue;
        filtered.add(doc);
      }
      yield filtered;
    }
  }

  Future<void> markRead(String chatId) async {
    try {
      await _db.collection('chats').doc(chatId).update({'unread': false});
    } catch (_) {}
  }

  Future<void> markMessagesRead({
    required String chatId,
    required String currentUid,
  }) async {
    try {
      final unread = await _db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUid)
          .get();
      final batch = _db.batch();
      for (final doc in unread.docs) {
        final readBy = List<String>.from(doc.data()['readBy'] ?? []);
        if (!readBy.contains(currentUid)) {
          batch.update(doc.reference, {
            'readBy': FieldValue.arrayUnion([currentUid]),
          });
        }
      }
      await batch.commit();
    } catch (_) {}
  }

  /// Επεξεργασία κειμένου μηνύματος (μόνο ο αποστολέας — το επιβάλλουν & τα
  /// Firestore rules). Σημειώνει `editedAt` για την ένδειξη «επεξεργασμένο».
  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String text,
  }) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'text': text,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Θέτει / αλλάζει / αφαιρεί την αντίδραση ΤΟΥ χρήστη σε ένα μήνυμα.
  /// Μοντέλο: reactions = { uid: emoji } — 1 αντίδραση ανά χρήστη.
  /// Αν ο χρήστης έχει ήδη το ΙΔΙΟ emoji → αφαιρείται (toggle off)· αλλιώς
  /// μπαίνει/αλλάζει. Ατομικό update ανά πεδίο (δεν πειράζει τα άλλα uids).
  Future<void> setMessageReaction({
    required String chatId,
    required String messageId,
    required String uid,
    required String emoji,
  }) async {
    final ref = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    final snap = await ref.get();
    final reactions =
        Map<String, dynamic>.from(snap.data()?['reactions'] ?? {});
    if (reactions[uid] == emoji) {
      await ref.update({'reactions.$uid': FieldValue.delete()});
    } else {
      await ref.update({'reactions.$uid': emoji});
    }
  }

  Future<void> setTyping({
    required String chatId,
    required String uid,
    required bool typing,
  }) async {
    try {
      await _db.collection('chats').doc(chatId).update({
        'typingUids': typing
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
      });
    } catch (_) {}
  }

  Stream<List<String>> watchTyping(String chatId) =>
      _db.collection('chats').doc(chatId).snapshots().map((snap) =>
          List<String>.from((snap.data()?['typingUids'] as List?) ?? []));

  Future<void> toggleMute({
    required String chatId,
    required String uid,
    required bool mute,
  }) async {
    await _db.collection('chats').doc(chatId).update({
      'mutedBy':
          mute ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
    });
  }

  /// Διαγραφή ολόκληρης της συνομιλίας (και για τους δύο — όπως και πριν).
  ///
  /// ΣΕΙΡΑ (σημαντική): 1) διάβασε τα μηνύματα, 2) σβήσε το chat doc,
  /// 3) σβήσε τα μηνύματα. Τα rules επιτρέπουν σε συμμετέχοντα να σβήσει
  /// μεμονωμένο μήνυμα ΜΟΝΟ αν είναι δικό του — αλλιώς ο ένας θα μπορούσε να
  /// εξαφανίζει τα μηνύματα του άλλου. Εξαίρεση: μηνύματα «ορφανά» (chat που
  /// δεν υπάρχει πια), δηλαδή ακριβώς αυτό το cleanup.
  Future<void> deleteChat(String chatId) async {
    final messages =
        await _db.collection('chats').doc(chatId).collection('messages').get();
    await _db.collection('chats').doc(chatId).delete();
    for (final msg in messages.docs) {
      try {
        await msg.reference.delete();
      } catch (e, s) {
        logSwallowed(e, s, 'deleteChat message cleanup');
      }
    }
  }

  /// Διαγραφή μηνύματος από τον αποστολέα (**soft delete**).
  ///
  /// Το μήνυμα ΔΕΝ εξαφανίζεται από τη ροή: μένει ως «Το μήνυμα διαγράφηκε»,
  /// ώστε ο συνομιλητής να βλέπει ότι κάτι γράφτηκε και αφαιρέθηκε — δεν
  /// ξαναγράφεται η ιστορία της συνομιλίας. Το περιεχόμενο (κείμενο και
  /// φωτογραφία/βίντεο) καθαρίζεται πραγματικά.
  ///
  /// Τα rules επιτρέπουν αυτό το write ΜΟΝΟ στον αποστολέα και ΜΟΝΟ προς τα
  /// εμπρός (δεν γίνεται «ξε-διαγραφή»).
  Future<void> deleteMessage(String chatId, String messageId) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'text': '',
      'mediaUrl': null,
    });
  }
}
