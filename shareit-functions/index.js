/**
 * ShareIt Cloud Functions - v2 με νέα δομή deal
 */

const {onDocumentWritten, onDocumentCreated} =
  require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
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
  // Defense-in-depth: τα Firestore rules ήδη επιβάλλουν ακέραιο 1–5, αλλά ο
  // server δεν εμπιστεύεται ποτέ την τιμή — αν φτάσει εκτός ορίων (π.χ. από
  // μελλοντικό μονοπάτι ή παρακαμμένο rules deploy), την απορρίπτει αντί να
  // εκτοξεύσει το rating του προφίλ.
  if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
    logger.warn(`applyRating: μη έγκυρο rating ${rating} για ${targetUid}`);
    return;
  }
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
    // `update` (όχι `set(merge)`): το set θα ΞΑΝΑΔΗΜΙΟΥΡΓΟΥΣΕ το doc ενός
    // χρήστη που έχει διαγράψει τον λογαριασμό του — ένα «φάντασμα» με μόνο
    // dealsCount, που δεν σβήνεται ποτέ και εμφανίζεται στην αναζήτηση.
    for (const uid of [after.user1Uid, after.user2Uid]) {
      if (!uid) continue;
      try {
        await db.collection("users").doc(uid)
            .update({dealsCount: FieldValue.increment(1)});
      } catch (e) {
        logger.error(`dealsCount ${uid} (διαγραμμένος;): ${e.message}`);
      }
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
 * Μετράει πόσοι ΔΙΑΦΟΡΕΤΙΚΟΙ χρήστες έχουν αναφέρει το ίδιο αντικείμενο.
 *
 * ΚΡΙΣΙΜΟ: μετράμε μοναδικούς `reporterUid`, ΟΧΙ πλήθος reports. Αλλιώς ένας
 * κακόβουλος χρήστης υποβάλλει 3 αναφορές μόνος του και κατεβάζει οποιοδήποτε
 * περιεχόμενο — το auto-hide θα γινόταν όπλο εναντίον αθώων.
 *
 * @param {string} field Το πεδίο ταυτοποίησης (listingId/postId/commentId…)
 * @param {string} value Η τιμή του
 * @return {Promise<number>} Πλήθος μοναδικών καταγγελλόντων
 */
async function uniqueReporters(field, value) {
  const snap = await db.collection("reports")
      .where(field, "==", value).get();
  const uids = new Set();
  snap.docs.forEach((d) => {
    const uid = d.data().reporterUid;
    if (uid) uids.add(uid);
  });
  return uids.size;
}

/**
 * Εφαρμόζει το πλήθος αναφορών σε ένα doc και κάνει auto-hide στο threshold.
 *
 * @param {FirebaseFirestore.DocumentReference} ref Το doc
 * @param {number} count Μοναδικοί καταγγέλλοντες
 * @param {boolean} canHide Αν επιτρέπεται απόκρυψη
 */
async function applyReportCount(ref, count, canHide) {
  const snap = await ref.get();
  if (!snap.exists) return;
  const update = {reportCount: count, isReported: true};
  if (canHide && count >= REPORT_AUTO_HIDE_THRESHOLD) {
    update.isHidden = true;
    update.hiddenReason = "auto_threshold";
  }
  await ref.update(update);
}

/**
 * Όταν δημιουργείται report: ενημερώνει τον counter στο αντικείμενο που
 * αναφέρθηκε (περιεχόμενο, αγγελία ή χρήστης) και κάνει auto-hide στο
 * threshold. Τρέχει με admin γιατί ο reporter δεν γράφει σε ξένο doc.
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

      const validCollection = postCollection === "wallPosts" ||
          postCollection === "userPosts";

      try {
        if (validCollection && postId && commentId) {
          // Σχόλιο μέσα σε post.
          const ref = db.collection(postCollection).doc(postId)
              .collection("comments").doc(commentId);
          await applyReportCount(
              ref, await uniqueReporters("commentId", commentId), true);
        } else if (validCollection && postId) {
          // Ολόκληρη ανάρτηση.
          const ref = db.collection(postCollection).doc(postId);
          await applyReportCount(
              ref, await uniqueReporters("postId", postId), true);
        } else if (listingId) {
          const ref = db.collection("listings").doc(listingId);
          await applyReportCount(
              ref, await uniqueReporters("listingId", listingId), true);
        }

        // Ο counter του ΧΡΗΣΤΗ ενημερώνεται πάντα (και για περιεχόμενο), αλλά
        // ΔΕΝ κρύβουμε ποτέ αυτόματα χρήστη — αυτό θέλει ανθρώπινη κρίση.
        if (targetUid) {
          const uref = db.collection("users").doc(targetUid);
          await applyReportCount(
              uref, await uniqueReporters("targetUid", targetUid), false);
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


// Τα ευαίσθητα πεδία που ΔΕΝ επιτρέπεται να μένουν στο δημόσιο user doc.
// Τα μεταφέρει στο users/{uid}/private/data το stripSensitiveFromUserDoc.
const SENSITIVE_FIELDS = ["email", "phone", "fcmToken", "language"];

// ΑΦΑΙΡΕΘΗΚΕ το `deleteUserAccount` από ΑΥΤΟ το codebase (us-central1).
// Ήταν ΔΙΠΛΟ: ο client καλεί την έκδοση του `push-notifications`
// (europe-west1).
// Η εδώ έκδοση ήταν αποκλίνουσα — ΔΕΝ ανωνυμοποιούσε τις αναφορές, δηλαδή αν
// ποτέ καλούνταν κατά λάθος θα παραβίαζε την πολιτική απορρήτου μας.

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
