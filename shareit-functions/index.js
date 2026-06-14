/**
 * ShareIt Cloud Functions - v2 με νέα δομή deal
 */

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {getStorage} = require("firebase-admin/storage");
const logger = require("firebase-functions/logger");

initializeApp();
const db = getFirestore();

/**
 * Δημιουργεί 2 wall posts όταν deal γίνει active.
 *
 * @param {string} dealId Το ID του deal
 * @param {object} dealData Τα data του deal
 */
async function createDealWallPost(dealId, dealData) {
  const existing = await db.collection("wallPosts")
      .where("dealId", "==", dealId).limit(1).get();
  if (!existing.empty) {
    logger.info(`Wall post για deal ${dealId} υπάρχει ήδη.`);
    return;
  }

  const user1Uid = dealData.user1Uid;
  const user2Uid = dealData.user2Uid;

  const [user1Doc, user2Doc] = await Promise.all([
    db.collection("users").doc(user1Uid).get(),
    db.collection("users").doc(user2Uid).get(),
  ]);

  const u1 = user1Doc.data() || {};
  const u2 = user2Doc.data() || {};

  const u1FullName = `${u1.firstName || ""} ${u1.lastName || ""}`.trim();
  const u2FullName = `${u2.firstName || ""} ${u2.lastName || ""}`.trim();

  const u1Friends = u1.friends || [];
  const u2Friends = u2.friends || [];
  const allowedCommenters = Array.from(new Set([
    user1Uid, user2Uid, ...u1Friends, ...u2Friends,
  ]));

  const proposal = dealData.proposal1 || dealData.proposal2 || {};

  const baseData = {
    dealId: dealId,
    type: "deal",
    title: proposal.title || dealData.listingTitle || "Deal",
    details: proposal.details || "",
    listingTitle: dealData.listingTitle || "",
    user1Uid: user1Uid,
    user2Uid: user2Uid,
    user1Name: u1FullName || "Χρήστης",
    user2Name: u2FullName || "Χρήστης",
    user1Avatar: u1.avatarUrl || null,
    user2Avatar: u2.avatarUrl || null,
    startDate: dealData.startDate || null,
    endDate: dealData.endDate || null,
    status: "active",
    dealStatus: "active",
    allowedCommenters: allowedCommenters,
    commentsCount: 0,
    createdAt: FieldValue.serverTimestamp(),
  };

  // 2 wall posts (ένα για κάθε χρήστη)
  await db.collection("wallPosts").add({
    ...baseData,
    targetUid: user1Uid,
    authorUid: user1Uid,
    authorName: u1FullName || "Χρήστης",
  });

  await db.collection("wallPosts").add({
    ...baseData,
    targetUid: user2Uid,
    authorUid: user2Uid,
    authorName: u2FullName || "Χρήστης",
  });

  logger.info(`✅ 2 wall posts για deal ${dealId}`);
}

/**
 * Mark wall posts as completed.
 *
 * @param {string} dealId Το ID του deal
 */
async function markWallPostsCompleted(dealId) {
  const snap = await db.collection("wallPosts")
      .where("dealId", "==", dealId).get();
  if (snap.empty) return;

  const batch = db.batch();
  snap.docs.forEach((doc) => {
    batch.update(doc.ref, {
      status: "completed",
      dealStatus: "completed",
      completedAt: FieldValue.serverTimestamp(),
    });
  });
  await batch.commit();
  logger.info(
      `${snap.size} wall posts -> completed για deal ${dealId}`);
}

/**
 * Complete deal + αύξηση dealsCount.
 *
 * @param {string} dealId Το ID του deal
 * @param {object} dealData Τα data του deal
 * @return {Promise<boolean>}
 */
async function completeDeal(dealId, dealData) {
  if (dealData.status === "completed") return false;
  if (dealData.status === "cancelled") return false;

  const user1Uid = dealData.user1Uid;
  const user2Uid = dealData.user2Uid;

  if (!user1Uid || !user2Uid) {
    logger.warn(`Deal ${dealId} χωρίς uids`);
    return false;
  }

  const batch = db.batch();

  batch.update(db.collection("deals").doc(dealId), {
    status: "completed",
    completedAt: FieldValue.serverTimestamp(),
  });

  batch.set(
      db.collection("users").doc(user1Uid),
      {dealsCount: FieldValue.increment(1)},
      {merge: true},
  );
  batch.set(
      db.collection("users").doc(user2Uid),
      {dealsCount: FieldValue.increment(1)},
      {merge: true},
  );

  await batch.commit();
  await markWallPostsCompleted(dealId);

  logger.info(`Deal ${dealId} ολοκληρώθηκε.`);
  return true;
}

exports.onDealUpdate = onDocumentWritten("deals/{dealId}", async (event) => {
  const after = event.data && event.data.after && event.data.after.data();
  if (!after) return null;

  const before = event.data && event.data.before && event.data.before.data();
  const dealId = event.params.dealId;

  const wasActive = before && before.status === "active";
  const isActive = after.status === "active";

  if (isActive && !wasActive) {
    logger.info(`Deal ${dealId} -> active. Creating wall posts.`);
    try {
      await createDealWallPost(dealId, after);
    } catch (e) {
      logger.error(`Αποτυχία wall post: ${e.message}`);
    }
  }

  // Auto-complete αν λήξει
  if (isActive) {
    const endDate = after.endDate;
    if (endDate) {
      const endDt = endDate.toDate();
      if (endDt <= new Date()) {
        logger.info(`Deal ${dealId} έληξε. Auto-completing.`);
        await completeDeal(dealId, after);
      }
    }
  }

  return null;
});

exports.checkExpiredDeals = onSchedule(
    {schedule: "every 1 hours", timeZone: "Europe/Athens"},
    async (event) => {
      logger.info("Έλεγχος για ληγμένα deals...");

      const now = new Date();
      const snapshot = await db.collection("deals")
          .where("status", "==", "active")
          .where("endDate", "<=", now)
          .get();

      if (snapshot.empty) {
        logger.info("Δεν βρέθηκαν ληγμένα.");
        return null;
      }

      logger.info(`Βρέθηκαν ${snapshot.size} ληγμένα deals.`);

      let completed = 0;
      for (const doc of snapshot.docs) {
        const ok = await completeDeal(doc.id, doc.data());
        if (ok) completed++;
      }

      logger.info(`Ολοκληρώθηκαν ${completed} deals.`);
      return null;
    },
);

/**
 * Σβήνει σε batches τα documents.
 *
 * @param {FirebaseFirestore.Query} query Query
 * @return {Promise<number>}
 */
async function deleteQueryBatch(query) {
  let totalDeleted = 0;
  let hasMore = true;

  while (hasMore) {
    const snapshot = await query.limit(400).get();
    if (snapshot.empty) {
      hasMore = false;
      break;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    totalDeleted += snapshot.size;

    if (snapshot.size < 400) hasMore = false;
  }
  return totalDeleted;
}

/**
 * Σβήνει υπο-collection.
 *
 * @param {FirebaseFirestore.Query} parentQuery Query
 * @param {string} subCollection Όνομα
 * @return {Promise<number>}
 */
async function deleteSubcollections(parentQuery, subCollection) {
  const parents = await parentQuery.get();
  let totalDeleted = 0;

  for (const parent of parents.docs) {
    const subRef = parent.ref.collection(subCollection);
    const deleted = await deleteQueryBatch(subRef);
    totalDeleted += deleted;
  }
  return totalDeleted;
}

/**
 * Σβήνει files.
 *
 * @param {string} uid User ID
 * @return {Promise<number>}
 */
async function deleteUserStorage(uid) {
  let deleted = 0;
  const bucket = getStorage().bucket();

  try {
    const [files] = await bucket.getFiles({prefix: `users/${uid}/`});
    for (const file of files) {
      await file.delete();
      deleted++;
    }
  } catch (e) {
    logger.warn(`Σφάλμα users/${uid}: ${e.message}`);
  }

  try {
    const [files] = await bucket.getFiles({prefix: `listings/${uid}/`});
    for (const file of files) {
      await file.delete();
      deleted++;
    }
  } catch (e) {
    logger.warn(`Σφάλμα listings/${uid}: ${e.message}`);
  }

  return deleted;
}

exports.deleteUserAccount = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Πρέπει να είσαι συνδεδεμένος.");
  }

  const uid = request.auth.uid;
  logger.info(`Διαγραφή χρήστη ${uid}`);

  const results = {
    listings: 0, chats: 0, messages: 0, deals: 0,
    notifications: 0, friendRequests: 0, wallPosts: 0, storageFiles: 0,
  };

  try {
    results.listings = await deleteQueryBatch(
        db.collection("listings").where("userId", "==", uid),
    );

    const chatsQuery = db.collection("chats")
        .where("participants", "array-contains", uid);
    results.messages = await deleteSubcollections(chatsQuery, "messages");
    results.chats = await deleteQueryBatch(chatsQuery);

    const dealsUser1 = db.collection("deals").where("user1Uid", "==", uid);
    const dealsUser2 = db.collection("deals").where("user2Uid", "==", uid);
    results.deals += await deleteQueryBatch(dealsUser1);
    results.deals += await deleteQueryBatch(dealsUser2);

    results.notifications = await deleteQueryBatch(
        db.collection("notifications").where("targetUid", "==", uid),
    );

    const frFrom = db.collection("friendRequests")
        .where("fromUid", "==", uid);
    const frTo = db.collection("friendRequests").where("toUid", "==", uid);
    results.friendRequests += await deleteQueryBatch(frFrom);
    results.friendRequests += await deleteQueryBatch(frTo);

    results.wallPosts = await deleteQueryBatch(
        db.collection("wallPosts").where("targetUid", "==", uid),
    );

    const friendsOf = await db.collection("users")
        .where("friends", "array-contains", uid).get();
    for (const friendDoc of friendsOf.docs) {
      await friendDoc.ref.update({
        friends: FieldValue.arrayRemove(uid),
      });
    }

    results.storageFiles = await deleteUserStorage(uid);

    await db.collection("users").doc(uid).delete();
    await getAuth().deleteUser(uid);

    logger.info(`Χρήστης ${uid} διαγράφηκε`, results);

    return {
      success: true,
      message: "Ο λογαριασμός σου διαγράφηκε επιτυχώς.",
      details: results,
    };
  } catch (error) {
    logger.error(`Σφάλμα διαγραφής ${uid}:`, error);
    throw new HttpsError("internal", `Αποτυχία: ${error.message}`);
  }
});
