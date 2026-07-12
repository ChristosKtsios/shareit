/**
 * ShareIt Cloud Functions - v2 με νέα δομή deal
 */

const {onDocumentWritten, onDocumentCreated} =
  require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, onRequest, HttpsError} =
  require("firebase-functions/v2/https");
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

  // Σημ.: το dealsCount ΔΕΝ αυξάνεται εδώ. Αυξάνεται μία φορά στο
  // onDealUpdate όταν ανιχνευθεί η μετάβαση status → "completed", ώστε να
  // μετριέται ακριβώς μία φορά ανεξάρτητα από ποιο path ολοκλήρωσε το deal.
  await db.collection("deals").doc(dealId).update({
    status: "completed",
    completedAt: FieldValue.serverTimestamp(),
  });

  await markWallPostsCompleted(dealId);

  logger.info(`Deal ${dealId} ολοκληρώθηκε.`);
  return true;
}

/**
 * Εφαρμόζει ένα rating στο προφίλ του target user (admin privileges).
 *
 * @param {string} targetUid Ο χρήστης που αξιολογείται
 * @param {number} rating Το rating (1-5)
 */
async function applyRating(targetUid, rating) {
  if (!targetUid || typeof rating !== "number") return;
  const userRef = db.collection("users").doc(targetUid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) return;
    const d = snap.data() || {};
    const cur = typeof d.rating === "number" ? d.rating : 0;
    const cnt = typeof d.ratingCount === "number" ? d.ratingCount : 0;
    const newCnt = cnt + 1;
    const newAvg = ((cur * cnt) + rating) / newCnt;
    tx.update(userRef, {rating: newAvg, ratingCount: newCnt});
  });
}

exports.onDealUpdate = onDocumentWritten("deals/{dealId}", async (event) => {
  const after = event.data && event.data.after && event.data.after.data();
  if (!after) return null;

  const before = event.data && event.data.before && event.data.before.data();
  const dealId = event.params.dealId;

  // ΓΕΦΥΡΑ: οι παλιές εκδόσεις δημιουργούν deals χωρίς `participants`. Χωρίς
  // αυτό το πεδίο, το deal δεν εμφανίζεται στις νέες εκδόσεις (που κάνουν
  // query με array-contains) και δεν το διαβάζουν τα rules. Το συμπληρώνουμε.
  if (!Array.isArray(after.participants) && after.user1Uid && after.user2Uid) {
    try {
      await db.collection("deals").doc(dealId).update({
        participants: [after.user1Uid, after.user2Uid],
      });
      logger.info(`Backfilled participants for deal ${dealId}`);
    } catch (e) {
      logger.error(`participants backfill ${dealId}: ${e.message}`);
    }
  }

  // ── RATINGS ──────────────────────────────────────────────
  // ownerRating = δόθηκε από user1 → εφαρμόζεται στον user2.
  // seekerRating = δόθηκε από user2 → εφαρμόζεται στον user1.
  // Εφαρμόζεται μόνο στη μετάβαση null → value (μία φορά ανά rating).
  if (after.ownerRating != null && (!before || before.ownerRating == null)) {
    try {
      await applyRating(after.user2Uid, after.ownerRating);
    } catch (e) {
      logger.error(`applyRating(owner) ${dealId}: ${e.message}`);
    }
  }
  if (after.seekerRating != null && (!before || before.seekerRating == null)) {
    try {
      await applyRating(after.user1Uid, after.seekerRating);
    } catch (e) {
      logger.error(`applyRating(seeker) ${dealId}: ${e.message}`);
    }
  }

  // ── dealsCount ───────────────────────────────────────────
  // Αυξάνεται ΜΙΑ φορά στη μετάβαση status → "completed", ανεξάρτητα από το
  // ποιο path (onDealUpdate expiry, scheduler, κ.λπ.) ολοκλήρωσε το deal.
  const wasCompleted = before && before.status === "completed";
  const isCompleted = after.status === "completed";
  if (isCompleted && !wasCompleted) {
    try {
      const batch = db.batch();
      if (after.user1Uid) {
        batch.set(db.collection("users").doc(after.user1Uid),
            {dealsCount: FieldValue.increment(1)}, {merge: true});
      }
      if (after.user2Uid) {
        batch.set(db.collection("users").doc(after.user2Uid),
            {dealsCount: FieldValue.increment(1)}, {merge: true});
      }
      await batch.commit();
    } catch (e) {
      logger.error(`dealsCount increment ${dealId}: ${e.message}`);
    }
  }

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

const REPORT_AUTO_HIDE_THRESHOLD = 3;

/**
 * Όταν δημιουργείται report, αυξάνει τον counter στο target (listing ή user)
 * και κάνει auto-hide στο listing όταν περάσει το threshold. Τρέχει με admin
 * privileges γιατί ο reporter δεν επιτρέπεται να γράψει σε ξένο doc.
 */
exports.onReportCreated = onDocumentCreated(
    "reports/{reportId}",
    async (event) => {
      const data = event.data && event.data.data();
      if (!data) return null;

      const listingId = data.listingId;
      const targetUid = data.targetUid;
      const postCollection = data.postCollection;
      const postId = data.postId;
      const commentId = data.commentId;

      // Το περιεχόμενο (post/σχόλιο) που αναφέρθηκε. Στα 3 reports κρύβεται
      // αυτόματα (isHidden) — ο client δεν το εμφανίζει πλέον.
      const contentRef = (postCollection === "wallPosts" ||
          postCollection === "userPosts") && postId ?
        (commentId ?
          db.collection(postCollection).doc(postId)
              .collection("comments").doc(commentId) :
          db.collection(postCollection).doc(postId)) :
        null;

      try {
        if (contentRef) {
          await db.runTransaction(async (tx) => {
            const snap = await tx.get(contentRef);
            if (!snap.exists) return;
            const count = ((snap.data().reportCount || 0)) + 1;
            const update = {reportCount: count, isReported: true};
            if (count >= REPORT_AUTO_HIDE_THRESHOLD) {
              update.isHidden = true;
              update.hiddenReason = "auto_threshold";
            }
            tx.update(contentRef, update);
          });
          // Ο counter του χρήστη που ανέβασε το περιεχόμενο ενημερώνεται
          // επίσης.
          if (targetUid) {
            const uref = db.collection("users").doc(targetUid);
            await db.runTransaction(async (tx) => {
              const snap = await tx.get(uref);
              if (!snap.exists) return;
              const count = ((snap.data().reportCount || 0)) + 1;
              tx.update(uref, {reportCount: count, isReported: true});
            });
          }
        } else if (listingId) {
          const ref = db.collection("listings").doc(listingId);
          await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            if (!snap.exists) return;
            const count = ((snap.data().reportCount || 0)) + 1;
            const update = {reportCount: count, isReported: true};
            if (count >= REPORT_AUTO_HIDE_THRESHOLD) {
              update.isHidden = true;
              update.hiddenReason = "auto_threshold";
            }
            tx.update(ref, update);
          });
        } else if (targetUid) {
          const ref = db.collection("users").doc(targetUid);
          await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            if (!snap.exists) return;
            const count = ((snap.data().reportCount || 0)) + 1;
            tx.update(ref, {reportCount: count, isReported: true});
          });
        }
      } catch (e) {
        logger.error(`onReportCreated ${event.params.reportId}: ${e.message}`);
      }
      return null;
    },
);

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

    // Private subcollection (email/phone/fcmToken) — δεν σβήνεται αυτόματα
    // με το parent doc.
    const priv = await db.collection("users").doc(uid)
        .collection("private").get();
    for (const doc of priv.docs) await doc.ref.delete();

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

/**
 * ΜΙΑ ΦΟΡΑ — μεταφορά υπαρχόντων δεδομένων στη νέα, ασφαλή δομή.
 *
 * 1) users: τα ευαίσθητα πεδία (email, phone, fcmToken, language) φεύγουν από
 *    το ΔΗΜΟΣΙΟ user doc (που το διαβάζει κάθε συνδεδεμένος χρήστης) και πάνε
 *    στο `users/{uid}/private/data` — αναγνώσιμο μόνο από τον ίδιο.
 * 2) deals: προστίθεται `participants: [user1Uid, user2Uid]`, ώστε τα rules να
 *    κλειδώνουν το read στους συμμετέχοντες (χωρίς αυτό, τα deals των παλιών
 *    docs δεν θα εμφανίζονταν).
 *
 * Είναι idempotent — μπορεί να ξανατρέξει με ασφάλεια.
 *
 * Κλήση (μία φορά, μετά το deploy των functions και ΠΡΙΝ το deploy των rules):
 *   curl "https://europe-west1-shareit-6cfa0.cloudfunctions.net/migrateToPrivateData?key=ΤΟ_ΚΛΕΙΔΙ"
 *
 * ΜΕΤΑ την επιτυχή εκτέλεση, ΣΒΗΣΕ αυτό το function και ξανακάνε deploy.
 */
const MIGRATION_SECRET = "115064955611d295351928ab3ade41b7";
const SENSITIVE_FIELDS = ["email", "phone", "fcmToken", "language"];

exports.migrateToPrivateData = onRequest(
    {region: "europe-west1", timeoutSeconds: 540},
    async (req, res) => {
      if (req.query.key !== MIGRATION_SECRET) {
        res.status(403).send("forbidden");
        return;
      }

      const report = {usersMigrated: 0, usersSkipped: 0, dealsMigrated: 0};

      const users = await db.collection("users").get();
      for (const doc of users.docs) {
        const d = doc.data();
        const priv = {};
        const strip = {};
        for (const f of SENSITIVE_FIELDS) {
          if (d[f] !== undefined && d[f] !== null) {
            priv[f] = d[f];
            strip[f] = FieldValue.delete();
          }
        }
        if (Object.keys(priv).length === 0) {
          report.usersSkipped++;
          continue;
        }
        try {
          // Πρώτα γράψε το private doc, ΜΕΤΑ σβήσε από το δημόσιο — ώστε αν
          // κάτι αποτύχει, να μη χαθούν δεδομένα.
          await doc.ref.collection("private").doc("data")
              .set(priv, {merge: true});
          await doc.ref.update(strip);
          report.usersMigrated++;
        } catch (e) {
          logger.error(`migrate user ${doc.id}:`, e);
        }
      }

      const deals = await db.collection("deals").get();
      for (const doc of deals.docs) {
        const d = doc.data();
        const cur = d.participants;
        if (Array.isArray(cur) && cur.length === 2) continue;
        const parts = [d.user1Uid, d.user2Uid].filter(Boolean);
        if (parts.length !== 2) continue;
        try {
          await doc.ref.update({participants: parts});
          report.dealsMigrated++;
        } catch (e) {
          logger.error(`migrate deal ${doc.id}:`, e);
        }
      }

      logger.info("migrateToPrivateData done", report);
      res.status(200).json(report);
    },
);

/**
 * ΓΕΦΥΡΑ ΣΥΜΒΑΤΟΤΗΤΑΣ (προσωρινή — μέχρι να ενημερωθούν όλοι οι χρήστες).
 *
 * Οι ΠΑΛΙΕΣ εκδόσεις της εφαρμογής γράφουν email/phone/fcmToken/language μέσα
 * στο ΔΗΜΟΣΙΟ user doc. Τα rules το επέτρεπαν, οπότε τα δεδομένα ήταν
 * αναγνώσιμα από κάθε χρήστη (η διαρροή που κλείσαμε).
 *
 * Αν απλώς τα απαγορεύσουμε, οι παλιοί clients σπάνε: το Google sign-in και η
 * εγγραφή αποτυγχάνουν, γιατί το write απορρίπτεται ολόκληρο.
 *
 * Λύση: τα rules τα δέχονται ξανά, ΑΛΛΑ αυτό το trigger τα μεταφέρει αμέσως
 * στο users/{uid}/private/data και τα σβήνει από το δημόσιο doc. Το παράθυρο
 * έκθεσης είναι ~1 δευτερόλεπτο αντί για μόνιμο.
 *
 * ΝΑ ΑΦΑΙΡΕΘΕΙ όταν όλοι οι χρήστες έχουν έκδοση ≥ 1.0.3 — τότε ξανακλειδώνουμε
 * τα rules (τα νέα builds δεν γράφουν ποτέ αυτά τα πεδία στο δημόσιο doc).
 */
exports.stripSensitiveFromUserDoc = onDocumentWritten(
    "users/{uid}",
    async (event) => {
      const after = event.data && event.data.after && event.data.after.data();
      if (!after) return null;

      const priv = {};
      const strip = {};
      for (const f of SENSITIVE_FIELDS) {
        if (after[f] !== undefined && after[f] !== null) {
          priv[f] = after[f];
          strip[f] = FieldValue.delete();
        }
      }
      if (Object.keys(priv).length === 0) return null;

      const uid = event.params.uid;
      try {
        // Πρώτα γράψε το private, ΜΕΤΑ σβήσε από το δημόσιο (χωρίς απώλεια).
        await db.collection("users").doc(uid)
            .collection("private").doc("data").set(priv, {merge: true});
        await db.collection("users").doc(uid).update(strip);
        const moved = Object.keys(priv).join(",");
        logger.info(`Stripped ${moved} from users/${uid}`);
      } catch (e) {
        logger.error(`stripSensitiveFromUserDoc ${uid}:`, e);
      }
      return null;
    },
);
