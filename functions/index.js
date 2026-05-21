const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

// Notification όταν έρχεται νέο μήνυμα
exports.onNewMessage = onDocumentCreated(
    "chats/{chatId}/messages/{messageId}",
    async (event) => {
      const message = event.data.data();
      const chatId  = event.params.chatId;

      const chatDoc = await admin.firestore()
          .collection("chats").doc(chatId).get();
      const chat = chatDoc.data();
      if (!chat) return;

      const senderId     = message.senderId;
      const participants = chat.participants || [];
      const recipientId  = participants.find((p) => p !== senderId);
      if (!recipientId) return;

      const userDoc = await admin.firestore()
          .collection("users").doc(recipientId).get();
      const fcmToken = userDoc.data()?.fcmToken;
      if (!fcmToken) return;

      const senderDoc = await admin.firestore()
          .collection("users").doc(senderId).get();
      const senderName = senderDoc.data()?.firstName || "Κάποιος";

      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: senderName,
          body: message.text || "Νέο μήνυμα",
        },
        data: {
          chatId:   chatId,
          senderId: senderId,
          type:     "message",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "shareit_messages",
            priority:  "high",
          },
        },
      });
    });

// Notification όταν γίνεται deal proposal
exports.onNewDealProposal = onDocumentUpdated(
    "deals/{dealId}",
    async (event) => {
      const before = event.data.before.data();
      const after  = event.data.after.data();
      const dealId = event.params.dealId;

      const newProposal1 = !before.proposal1 && after.proposal1;
      const newProposal2 = !before.proposal2 && after.proposal2;
      if (!newProposal1 && !newProposal2) return;

      const senderId    = newProposal1 ? after.user1Uid : after.user2Uid;
      const recipientId = newProposal1 ? after.user2Uid : after.user1Uid;

      const userDoc = await admin.firestore()
          .collection("users").doc(recipientId).get();
      const fcmToken = userDoc.data()?.fcmToken;
      if (!fcmToken) return;

      const senderDoc = await admin.firestore()
          .collection("users").doc(senderId).get();
      const senderName = senderDoc.data()?.firstName || "Κάποιος";

      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: "Νέα πρόταση Deal!",
          body:  `${senderName} σου έστειλε πρόταση για deal`,
        },
        data: {
          dealId: dealId,
          chatId: after.chatId,
          type:   "deal_proposal",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "shareit_messages",
            priority:  "high",
          },
        },
      });
    });

// Όταν ολοκληρώνεται deal → φίλοι + deals count
exports.onDealCompleted = onDocumentUpdated(
    "deals/{dealId}",
    async (event) => {
      const before = event.data.before.data();
      const after  = event.data.after.data();

      if (before.status === after.status) return;
      if (after.status !== "completed") return;

      const user1Uid = after.user1Uid;
      const user2Uid = after.user2Uid;

      await admin.firestore()
          .collection("users").doc(user1Uid).update({
            friends:    admin.firestore.FieldValue.arrayUnion(user2Uid),
            dealsCount: admin.firestore.FieldValue.increment(1),
          });

      await admin.firestore()
          .collection("users").doc(user2Uid).update({
            friends:    admin.firestore.FieldValue.arrayUnion(user1Uid),
            dealsCount: admin.firestore.FieldValue.increment(1),
          });

      // Ενημέρωσε τα wall posts σε completed
      const wallPostsSnap = await admin.firestore()
          .collection("wallPosts")
          .where("dealId", "==", event.params.dealId)
          .get();

      const batch = admin.firestore().batch();
      wallPostsSnap.docs.forEach((doc) => {
        batch.update(doc.ref, { dealStatus: "completed" });
      });
      await batch.commit();
    });

// Όταν γίνεται accepted το deal → δημιούργησε wall post
exports.onDealAccepted = onDocumentUpdated(
    "deals/{dealId}",
    async (event) => {
      const before = event.data.before.data();
      const after  = event.data.after.data();

      // Μόνο όταν αλλάζει σε active
      if (before.status === after.status) return;
      if (after.status !== "active") return;

      const user1Uid = after.user1Uid;
      const user2Uid = after.user2Uid;
      const dealId   = event.params.dealId;

      const [user1Doc, user2Doc] = await Promise.all([
        admin.firestore().collection("users").doc(user1Uid).get(),
        admin.firestore().collection("users").doc(user2Uid).get(),
      ]);

      const user1Name = user1Doc.data()?.firstName || "Χρήστης";
      const user2Name = user2Doc.data()?.firstName || "Χρήστης";

      // Wall post για user1
      await admin.firestore().collection("wallPosts").add({
        targetUid:    user1Uid,
        authorUid:    user2Uid,
        authorName:   user2Name,
        text:         `Συμφωνήσαμε για ανταλλαγή: ${after.listingTitle}`,
        listingTitle: after.listingTitle,
        dealId:       dealId,
        dealStatus:   "active",
        deliveryAt:   after.deliveryAt,
        rating:       0,
        createdAt:    admin.firestore.FieldValue.serverTimestamp(),
      });

      // Wall post για user2
      await admin.firestore().collection("wallPosts").add({
        targetUid:    user2Uid,
        authorUid:    user1Uid,
        authorName:   user1Name,
        text:         `Συμφωνήσαμε για ανταλλαγή: ${after.listingTitle}`,
        listingTitle: after.listingTitle,
        dealId:       dealId,
        dealStatus:   "active",
        deliveryAt:   after.deliveryAt,
        rating:       0,
        createdAt:    admin.firestore.FieldValue.serverTimestamp(),
      });

      // Notification στους 2 χρήστες
      const [token1, token2] = [
        user1Doc.data()?.fcmToken,
        user2Doc.data()?.fcmToken,
      ];

      const notifications = [];
      if (token1) {
        notifications.push(admin.messaging().send({
          token: token1,
          notification: {
            title: "Deal ενεργοποιήθηκε! 🤝",
            body:  `Η ανταλλαγή για "${after.listingTitle}" ξεκίνησε!`,
          },
          data: { dealId: dealId, type: "deal_active" },
        }));
      }
      if (token2) {
        notifications.push(admin.messaging().send({
          token: token2,
          notification: {
            title: "Deal ενεργοποιήθηκε! 🤝",
            body:  `Η ανταλλαγή για "${after.listingTitle}" ξεκίνησε!`,
          },
          data: { dealId: dealId, type: "deal_active" },
        }));
      }
      await Promise.all(notifications);
    });