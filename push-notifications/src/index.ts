import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions";
import * as logger from "firebase-functions/logger";

admin.initializeApp();
setGlobalOptions({ maxInstances: 10, region: "europe-west1" });

const db = admin.firestore();
const messaging = admin.messaging();
const auth = admin.auth();

// ── i18n των push notifications ──
// Ο κάθε χρήστης αποθηκεύει τη γλώσσα του (`language`: el/en/es) στο user doc
// (γράφεται από τον client). Τα push συντάσσονται στη γλώσσα του ΠΑΡΑΛΗΠΤΗ.
type Lang = "el" | "en" | "es";
const SUPPORTED: Lang[] = ["el", "en", "es"];

const STR: Record<string, Record<Lang, string>> = {
  newMessageTitle: { el: "Νέο μήνυμα", en: "New message", es: "Nuevo mensaje" },
  msgPhoto: { el: "📷 Φωτογραφία", en: "📷 Photo", es: "📷 Foto" },
  msgVideo: { el: "🎥 Βίντεο", en: "🎥 Video", es: "🎥 Vídeo" },
  msgDealProposal: {
    el: "📋 Πρόταση Deal", en: "📋 Deal proposal", es: "📋 Propuesta de deal",
  },
  msgDealClosed: {
    el: "🤝 Το deal έκλεισε", en: "🤝 Deal closed", es: "🤝 Deal cerrado",
  },
  someone: { el: "Κάποιος", en: "Someone", es: "Alguien" },
  dealProposalTitle: {
    el: "🤝 Νέα πρόταση deal",
    en: "🤝 New deal proposal",
    es: "🤝 Nueva propuesta de deal",
  },
  dealProposalBody: {
    el: "Ο/Η {name} σου έστειλε πρόταση deal",
    en: "{name} sent you a deal proposal",
    es: "{name} te envió una propuesta de deal",
  },
  friendReqTitle: {
    el: "👋 Νέο αίτημα φιλίας",
    en: "👋 New friend request",
    es: "👋 Nueva solicitud de amistad",
  },
  friendReqBody: {
    el: "Ο/Η {name} θέλει να γίνετε φίλοι",
    en: "{name} wants to be your friend",
    es: "{name} quiere ser tu amigo",
  },
};

function t(lang: string, key: string, args: Record<string, string> = {}): string {
  const l: Lang = (SUPPORTED as string[]).includes(lang) ? (lang as Lang) : "el";
  let s = STR[key]?.[l] ?? STR[key]?.el ?? "";
  for (const [k, v] of Object.entries(args)) s = s.split(`{${k}}`).join(v);
  return s;
}

type Msg = { title: string; body: string };

/** Το private doc του χρήστη: email/phone/fcmToken/language. Δεν είναι
 *  αναγνώσιμο από άλλους χρήστες (firestore.rules) — εδώ το διαβάζουμε με
 *  admin. Fallback στο δημόσιο doc για χρήστες που δεν έχουν ακόμα migrated. */
function privateRef(uid: string) {
  return db.collection("users").doc(uid).collection("private").doc("data");
}

async function sendToUser(
  uid: string,
  build: (lang: string) => Msg,
  data: Record<string, string> = {}
): Promise<void> {
  const [userDoc, privDoc] = await Promise.all([
    db.collection("users").doc(uid).get(),
    privateRef(uid).get(),
  ]);
  const priv = privDoc.data() ?? {};
  const pub = userDoc.data() ?? {};
  const lang = (priv.language as string) ?? (pub.language as string) ?? "el";
  const tokens: string[] = priv.fcmTokens ?? pub.fcmTokens ?? [];
  if (tokens.length === 0) {
    const single = priv.fcmToken ?? pub.fcmToken;
    if (typeof single === "string" && single.length > 0) tokens.push(single);
  }
  if (tokens.length === 0) {
    logger.info(`No FCM tokens for user ${uid}`);
    return;
  }
  const { title, body } = build(lang);
  const payload = {
    notification: { title, body },
    data,
    android: {
      priority: "high" as const,
      notification: { channelId: "shareit_messages", sound: "default" },
    },
  };
  for (const token of tokens) {
    try {
      await messaging.send({ token, ...payload });
    } catch (err) {
      logger.error(`Send to ${token} failed`, err);
    }
  }
}

export const onNewMessage = onDocumentCreated(
  "chats/{chatId}/messages/{msgId}",
  async (event) => {
    const msg = event.data?.data();
    if (!msg) return;
    const chatId = event.params.chatId;
    const senderId = msg.senderId as string;
    const msgType = (msg.messageType as string) ?? "text";
    const chatDoc = await db.collection("chats").doc(chatId).get();
    const chatData = chatDoc.data();
    const participants = (chatData?.participants as string[]) ?? [];
    const receiverId = participants.find((p) => p !== senderId);
    if (!receiverId) return;
    
    // ✅ ΕΛΕΓΧΟΣ MUTE — μη στείλεις push αν ο receiver έχει σιγάσει το chat
    const mutedBy = (chatData?.mutedBy as string[]) ?? [];
    if (mutedBy.includes(receiverId)) {
      logger.info(`Chat ${chatId} muted by ${receiverId}, skipping push`);
      return;
    }
    
    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderName: string | undefined =
      senderDoc.data()?.firstName ?? senderDoc.data()?.fullName;
    await sendToUser(receiverId, (lang) => {
      let body: string;
      switch (msgType) {
      case "image": body = t(lang, "msgPhoto"); break;
      case "video": body = t(lang, "msgVideo"); break;
      case "deal_proposal": body = t(lang, "msgDealProposal"); break;
      case "deal_closed": body = t(lang, "msgDealClosed"); break;
      default: body = (msg.text as string) ?? t(lang, "newMessageTitle");
      }
      return { title: senderName ?? t(lang, "newMessageTitle"), body };
    }, { type: "chat", chatId });
  }
);

export const onNewNotification = onDocumentCreated(
  "notifications/{notifId}",
  async (event) => {
    const n = event.data?.data();
    if (!n) return;
    const targetUid = n.targetUid as string;
    const title = (n.title as string) ?? "ShareIt";
    const body = (n.body as string) ?? "";
    const type = (n.type as string) ?? "general";
    await sendToUser(targetUid, () => ({ title, body }),
      { type, notifId: event.params.notifId });
  }
);

// Deal proposals are created in two steps: an empty `pending` doc, then an
// `update` that sets `proposal1`. We notify the receiver on that update (when
// proposal1 transitions null → set), not on the empty creation.
export const onDealProposalSent = onDocumentUpdated(
  "deals/{dealId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;

    const hadProposal = before?.proposal1 != null;
    const hasProposal = after.proposal1 != null;
    if (hadProposal || !hasProposal) return; // only on the null → set edge

    const user1 = after.user1Uid as string;
    const user2 = after.user2Uid as string;
    const proposerUid = (after.proposerUid as string) ?? user1;
    const receiverId = proposerUid === user1 ? user2 : user1;
    if (!receiverId) return;

    const proposerDoc = await db.collection("users").doc(proposerUid).get();
    const proposerName = proposerDoc.data()?.firstName as string | undefined;
    await sendToUser(receiverId, (lang) => ({
      title: t(lang, "dealProposalTitle"),
      body: t(lang, "dealProposalBody",
        { name: proposerName ?? t(lang, "someone") }),
    }), { type: "deal", dealId: event.params.dealId });
  }
);

export const onNewPostComment = onDocumentCreated(
  "userPosts/{postId}/comments/{commentId}",
  async (event) => {
    const comment = event.data?.data();
    if (!comment) return;
    const postId = event.params.postId;
    const authorUid = comment.authorUid as string;
    const text = (comment.text as string) ?? "";
    const postDoc = await db.collection("userPosts").doc(postId).get();
    const postAuthorUid = postDoc.data()?.authorUid as string;
    if (!postAuthorUid || postAuthorUid === authorUid) return;
    const commenterName = comment.authorName as string | undefined;
    const preview = text.length > 80 ? text.substring(0, 80) + "..." : text;
    await sendToUser(postAuthorUid, (lang) => ({
      title: `💬 ${commenterName ?? t(lang, "someone")}`,
      body: preview,
    }), { type: "post_comment", postId });
  }
);

/**
 * Ελέγχει (authoritative, μέσω Firebase Auth admin) αν υπάρχει ήδη λογαριασμός
 * με το δοσμένο email ή/και κινητό. Καλείται ΠΡΙΝ το OTP στην εγγραφή ώστε να
 * μη γίνεται unauthenticated query στους users και να μη χρειάζεται sign-in.
 */
export const checkAccountExists = onCall(
  { enforceAppCheck: false }, // ΠΡΟΣΩΡΙΝΟ: off μέχρι να ρυθμιστεί Play Integrity (ήταν true)
  async (request) => {
  const email = ((request.data?.email as string) ?? "").trim();
  const phone = ((request.data?.phone as string) ?? "").trim();

  let emailExists = false;
  let phoneExists = false;

  if (email) {
    try {
      await auth.getUserByEmail(email);
      emailExists = true;
    } catch {
      emailExists = false;
    }
  }
  if (phone) {
    try {
      const user = await auth.getUserByPhoneNumber(phone);
      // ΕΝΙΑΙΟΣ ΟΡΙΣΜΟΣ "ΠΛΗΡΟΥΣ" ΛΟΓΑΡΙΑΣΜΟΥ: υπάρχει profile doc ΚΑΙ email
      // (email/password linked). Τα half-accounts (doc χωρίς email, ή orphan
      // phone-only χωρίς doc) ΔΕΝ μπλοκάρουν την εγγραφή — η ροή εγγραφής τα
      // ΕΠΙΣΚΕΥΑΖΕΙ (repair). ΔΕΝ σβήνουμε τίποτα εδώ.
      const doc = await db.collection("users").doc(user.uid).get();
      phoneExists = doc.exists && !!user.email;
    } catch {
      phoneExists = false;
    }
  }

  return { emailExists, phoneExists };
});

/**
 * Επιστρέφει το email που αντιστοιχεί σε ένα κινητό (admin, μέσω Firebase
 * Auth). Το χρειάζεται το login-με-κινητό και το forgot-password-με-κινητό,
 * που τρέχουν από ΜΗ συνδεδεμένο χρήστη (δεν επιτρέπεται query στους users).
 */
export const getEmailByPhone = onCall(
  { enforceAppCheck: false }, // ΠΡΟΣΩΡΙΝΟ: off μέχρι να ρυθμιστεί Play Integrity (ήταν true)
  async (request) => {
  const phone = ((request.data?.phone as string) ?? "").trim();
  if (!phone) return { email: null, accountExists: false };
  try {
    const user = await auth.getUserByPhoneNumber(phone);
    // accountExists: υπάρχει Auth phone user (έστω κι αν είναι half-account
    // χωρίς email). Επιτρέπει στον client να ξεχωρίσει "δεν υπάρχει" από
    // "υπάρχει αλλά ημιτελής".
    return { email: user.email ?? null, accountExists: true };
  } catch {
    return { email: null, accountExists: false };
  }
});

export const onNewFriendRequest = onDocumentCreated(
  "friendRequests/{reqId}",
  async (event) => {
    const req = event.data?.data();
    if (!req) return;
    const fromUid = req.fromUid as string;
    const toUid = req.toUid as string;
    const fromDoc = await db.collection("users").doc(fromUid).get();
    const fromName = fromDoc.data()?.firstName as string | undefined;
    await sendToUser(toUid, (lang) => ({
      title: t(lang, "friendReqTitle"),
      body: t(lang, "friendReqBody", { name: fromName ?? t(lang, "someone") }),
    }), { type: "friend_request", fromUid });
  }
);

/**
 * ΦΙΛΙΑ — γράφεται ΜΟΝΟ εδώ (server), ποτέ από τον client.
 *
 * Ο client δεν μπορεί να γράψει το `friends` άλλου χρήστη (firestore.rules):
 * αλλιώς οποιοσδήποτε θα αυτοπροστίθετο στη λίστα φίλων σου και θα αποκτούσε
 * πρόσβαση σε ιδιωτικό προφίλ/σχόλια χωρίς ποτέ να τον δεχτείς.
 *
 * Τα rules επιτρέπουν `status: accepted` ΜΟΝΟ στον παραλήπτη (toUid) και μόνο
 * από `pending` — οπότε το trigger εδώ είναι αξιόπιστο σήμα αποδοχής.
 */
export const onFriendRequestAccepted = onDocumentUpdated(
  "friendRequests/{reqId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;
    if (before?.status === "accepted" || after.status !== "accepted") return;

    const fromUid = after.fromUid as string;
    const toUid = after.toUid as string;
    if (!fromUid || !toUid || fromUid === toUid) return;

    const batch = db.batch();
    batch.set(
      db.collection("users").doc(fromUid),
      { friends: admin.firestore.FieldValue.arrayUnion(toUid) },
      { merge: true }
    );
    batch.set(
      db.collection("users").doc(toUid),
      { friends: admin.firestore.FieldValue.arrayUnion(fromUid) },
      { merge: true }
    );
    await batch.commit();
    logger.info(`Friendship created: ${fromUid} <-> ${toUid}`);
  }
);

/** Κατάργηση φιλίας — αφαιρεί και τις δύο πλευρές. */
export const unfriendUser = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Πρέπει να είσαι συνδεδεμένος");

  const targetUid = ((request.data?.targetUid as string) ?? "").trim();
  if (!targetUid || targetUid === uid) {
    throw new HttpsError("invalid-argument", "Μη έγκυρος χρήστης");
  }

  const batch = db.batch();
  batch.update(db.collection("users").doc(uid), {
    friends: admin.firestore.FieldValue.arrayRemove(targetUid),
  });
  batch.update(db.collection("users").doc(targetUid), {
    friends: admin.firestore.FieldValue.arrayRemove(uid),
  });
  await batch.commit();

  // Καθάρισε τα αιτήματα μεταξύ τους, ώστε να μπορούν να ξαναγίνουν φίλοι.
  const [a, b] = await Promise.all([
    db.collection("friendRequests")
      .where("fromUid", "==", uid).where("toUid", "==", targetUid).get(),
    db.collection("friendRequests")
      .where("fromUid", "==", targetUid).where("toUid", "==", uid).get(),
  ]);
  for (const doc of [...a.docs, ...b.docs]) {
    try { await doc.ref.delete(); } catch (e) { logger.error(`fr ${doc.id}:`, e); }
  }

  return { success: true };
});

/**
 * GDPR-compliant διαγραφή λογαριασμού.
 * Διαγράφει: listings, deals, chats, wall posts, user posts, friends,
 * notifications, user document, FirebaseAuth user.
 */
export const deleteUserAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    logger.error("Unauthenticated delete attempt");
    throw new HttpsError("unauthenticated", "Πρέπει να είσαι συνδεδεμένος");
  }

  logger.info(`Starting account deletion for user: ${uid}`);

  try {
    // ΣΕΙΡΑ: πρώτα ΟΛΑ τα Firestore/Storage δεδομένα, και ΤΕΛΕΥΤΑΙΟ ο Auth
    // λογαριασμός — ώστε αν κάτι αποτύχει, ο χρήστης μπορεί ακόμα να μπει και
    // να ξαναπροσπαθήσει (όχι μη-αναστρέψιμη μερική διαγραφή).

    // 2. Διαγραφή listings
    const listings = await db.collection("listings").where("userId", "==", uid).get();
    for (const doc of listings.docs) {
      try { await doc.ref.delete(); } catch (e) { logger.error(`listing ${doc.id}:`, e); }
    }
    logger.info(`Deleted ${listings.size} listings`);

    // 3. Διαγραφή deals
    const dealsAsUser1 = await db.collection("deals").where("user1Uid", "==", uid).get();
    const dealsAsUser2 = await db.collection("deals").where("user2Uid", "==", uid).get();
    for (const doc of [...dealsAsUser1.docs, ...dealsAsUser2.docs]) {
      try { await doc.ref.delete(); } catch (e) { logger.error(`deal ${doc.id}:`, e); }
    }
    logger.info(`Deleted ${dealsAsUser1.size + dealsAsUser2.size} deals`);

    // 4. Διαγραφή chats + messages
    const chats = await db.collection("chats").where("participants", "array-contains", uid).get();
    for (const doc of chats.docs) {
      try {
        const messages = await doc.ref.collection("messages").get();
        for (const msg of messages.docs) await msg.ref.delete();
        await doc.ref.delete();
      } catch (e) { logger.error(`chat ${doc.id}:`, e); }
    }
    logger.info(`Deleted ${chats.size} chats`);

    // 5. Διαγραφή wall posts
    const wallPosts = await db.collection("wallPosts").where("authorUid", "==", uid).get();
    for (const doc of wallPosts.docs) {
      try {
        const comments = await doc.ref.collection("comments").get();
        for (const c of comments.docs) await c.ref.delete();
        await doc.ref.delete();
      } catch (e) { logger.error(`wallPost ${doc.id}:`, e); }
    }

    // 6. Διαγραφή user posts
    const userPosts = await db.collection("userPosts").where("authorUid", "==", uid).get();
    for (const doc of userPosts.docs) {
      try {
        const comments = await doc.ref.collection("comments").get();
        for (const c of comments.docs) await c.ref.delete();
        await doc.ref.delete();
      } catch (e) { logger.error(`userPost ${doc.id}:`, e); }
    }

    // 7. Friend requests
    const fromMe = await db.collection("friendRequests").where("fromUid", "==", uid).get();
    const toMe = await db.collection("friendRequests").where("toUid", "==", uid).get();
    for (const doc of [...fromMe.docs, ...toMe.docs]) {
      try { await doc.ref.delete(); } catch (e) { logger.error(`fr ${doc.id}:`, e); }
    }

    // 8. Notifications
    const notifs = await db.collection("notifications").where("targetUid", "==", uid).get();
    for (const doc of notifs.docs) {
      try { await doc.ref.delete(); } catch (e) { logger.error(`notif ${doc.id}:`, e); }
    }

    // 9. Αφαίρεση από friends λίστες
    const usersWithFriend = await db.collection("users").where("friends", "array-contains", uid).get();
    for (const doc of usersWithFriend.docs) {
      try {
        await doc.ref.update({ friends: admin.firestore.FieldValue.arrayRemove(uid) });
      } catch (e) { logger.error(`user friends ${doc.id}:`, e); }
    }

    // 9b. Storage files (avatars/φωτο profile + listings)
    try {
      const bucket = admin.storage().bucket();
      await bucket.deleteFiles({ prefix: `users/${uid}/` });
      await bucket.deleteFiles({ prefix: `listings/${uid}/` });
    } catch (e) { logger.error("storage delete failed:", e); }

    // 10. Διαγραφή user document + private subcollection (email/phone/token)
    try {
      const priv = await db.collection("users").doc(uid).collection("private").get();
      for (const doc of priv.docs) await doc.ref.delete();
      await db.collection("users").doc(uid).delete();
      logger.info(`User document ${uid} deleted`);
    } catch (e) { logger.error("user doc delete failed:", e); }

    // 11. Διαγραφή Auth user ΤΕΛΕΥΤΑΙΟ — αφού καθαρίστηκαν όλα τα δεδομένα.
    try {
      await auth.deleteUser(uid);
      logger.info(`Firebase Auth user ${uid} deleted`);
    } catch (authErr) {
      logger.warn(`Auth delete failed (might be already deleted): ${authErr}`);
    }

    logger.info(`Account deletion complete for ${uid}`);
    return { success: true };
  } catch (err) {
    logger.error("Critical error deleting account:", err);
    throw new HttpsError("internal", `Αποτυχία διαγραφής: ${err}`);
  }
});

/**
 * Scheduled function — τρέχει κάθε μέρα στις 03:00 UTC
 * και διαγράφει αγγελίες με availableUntil στο παρελθόν.
 */
export const deleteExpiredListings = onSchedule(
  {
    schedule: "every day 03:00",
    timeZone: "Europe/Athens",
    region: "europe-west1",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db
      .collection("listings")
      .where("availableUntil", "<", now)
      .get();

    let deleted = 0;
    for (const doc of snap.docs) {
      try {
        await doc.ref.delete();
        deleted++;
      } catch (err) {
        logger.error(`Failed to delete listing ${doc.id}:`, err);
      }
    }
    logger.info(`Deleted ${deleted} expired listings`);
  }
);

/**
 * AUTO-TRANSITION ACTIVE → COMPLETED
 * Τρέχει κάθε 1 λεπτό και αλλάζει το status των deals που έχουν λήξει.
 */
export const autoCompleteExpiredDeals = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "Europe/Athens",
    region: "europe-west1",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db
      .collection("deals")
      .where("status", "==", "active")
      .where("endDate", "<=", now)
      .get();

    if (snap.empty) {
      logger.info("No expired deals to complete");
      return;
    }

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.update(doc.ref, {
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info(`Marking deal ${doc.id} as completed`);
    }
    await batch.commit();

    // Ενημέρωση wall posts → dealStatus: completed
    const wallSnap = await db
      .collection("wallPosts")
      .where("dealStatus", "==", "active")
      .where("dealId", "in", snap.docs.map(d => d.id).slice(0, 30))
      .get();
    
    if (!wallSnap.empty) {
      const wallBatch = db.batch();
      for (const wp of wallSnap.docs) {
        wallBatch.update(wp.ref, {
          dealStatus: "completed",
          status: "completed",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await wallBatch.commit();
    }

    logger.info(`Completed ${snap.docs.length} deals`);
  }
);
