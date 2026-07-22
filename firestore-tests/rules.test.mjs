import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, addDoc,
  query, where, getDocs, orderBy, arrayUnion, arrayRemove, increment,
  deleteField, serverTimestamp,
} from "firebase/firestore";

const env = await initializeTestEnvironment({
  projectId: "demo-shareit",
  firestore: { host: "127.0.0.1", port: 8098 },
});

const ALICE = "alice";
const BOB = "bob";
const MALLORY = "mallory";

// Η Alice είναι πλήρως εγγεγραμμένη χρήστρια → το token της έχει το claim
// `phone_number` (όπως μετά το OTP + getIdToken(true)). Το χρειάζεται για να
// δηλώσει phoneVerified:true, σύμφωνα με το phoneVerifiedIsGenuine() των rules.
const alice = env.authenticatedContext(ALICE, { phone_number: "+306900000000" }).firestore();
const bob = env.authenticatedContext(BOB).firestore();
const mallory = env.authenticatedContext(MALLORY).firestore();

let pass = 0, fail = 0;
const results = [];
async function check(name, fn) {
  try { await fn(); pass++; results.push(`  ✅ ${name}`); }
  catch (e) { fail++; results.push(`  ❌ ${name}\n       ${String(e).split("\n")[0].slice(0, 160)}`); }
}

// ── seed (bypasses rules) ──────────────────────────────────────────────
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const uid of [ALICE, BOB, MALLORY]) {
    await setDoc(doc(db, "users", uid), {
      uid, firstName: uid, lastName: "T", rating: 0, ratingCount: 0,
      dealsCount: 0, blockedUids: [], savedListingIds: [],
      // Η Alice έχει ήδη φίλο τον Bob — ώστε το τεστ «σβήσιμο φίλων άλλου» να
      // έχει πραγματικά κάτι να σβήσει.
      friends: uid === ALICE ? [BOB] : [],
    });
    await setDoc(doc(db, "users", uid, "private", "data"),
      { email: `${uid}@x.com`, phone: "+3069", fcmToken: "tok" });
  }
  await setDoc(doc(db, "chats", "chatAB"), {
    participants: [ALICE, BOB], lastMessage: "hi", unread: false,
  });
  await setDoc(doc(db, "chats", "chatAB", "messages", "mA"),
    { senderId: ALICE, text: "from alice", readBy: [], reactions: {} });
  await setDoc(doc(db, "chats", "chatAB", "messages", "mB"),
    { senderId: BOB, text: "from bob", readBy: [], reactions: {} });
  await setDoc(doc(db, "deals", "dealAB"), {
    chatId: "chatAB", participants: [ALICE, BOB], user1Uid: ALICE, user2Uid: BOB,
    status: "pending", createdAt: new Date(),
  });
  // Ολοκληρωμένο deal — βάση για τα tests αξιολόγησης.
  await setDoc(doc(db, "deals", "dealDone"), {
    chatId: "chatAB", participants: [ALICE, BOB], user1Uid: ALICE, user2Uid: BOB,
    status: "completed", ownerRating: null, seekerRating: null,
    createdAt: new Date(),
  });
  await setDoc(doc(db, "notifications", "n1"),
    { targetUid: ALICE, title: "t", body: "b", isRead: false });
  await setDoc(doc(db, "tags", "sport"), { name: "sport", count: 5 });
  await setDoc(doc(db, "wallPosts", "wp1"),
    { authorUid: ALICE, targetUid: ALICE, likes: [BOB], commentsCount: 1 });
  // Post που κρύφτηκε από reports (3+ αναφορές, server-side).
  await setDoc(doc(db, "userPosts", "up_hidden"), {
    authorUid: ALICE, text: "spam", likes: [],
    reportCount: 3, isReported: true, isHidden: true, hiddenReason: "auto_threshold",
  });
  await setDoc(doc(db, "friendRequests", "fr1"),
    { fromUid: ALICE, toUid: BOB, status: "pending" });
  await setDoc(doc(db, "listings", "l1"),
    { userId: ALICE, title: "x", isHidden: true, reportCount: 3, isReported: true });
});

console.log("\n🔴 ΕΠΙΘΕΣΕΙΣ (πρέπει να ΑΠΟΡΡΙΠΤΟΝΤΑΙ)");

await check("#1 Mallory ΔΕΝ διαβάζει το email/τηλέφωνο της Alice", () =>
  assertFails(getDoc(doc(mallory, "users", ALICE, "private", "data"))));

// Ο χρήστης ΕΝΗΜΕΡΩΝΕΙ το ΔΙΚΟ του δημόσιο doc με μη-ευαίσθητο πεδίο → OK.
await check("Mallory ενημερώνει το δικό της δημόσιο doc (μη-PII) → OK", () =>
  assertSucceeds(updateDoc(doc(mallory, "users", MALLORY), { firstName: "Mallory2" })));

// PII ΔΕΝ επιτρέπεται στο δημόσιο doc (το διαβάζουν όλοι → doxxing). Ζει μόνο
// στο users/{uid}/private/data. Καλύπτει create ΚΑΙ update, email/phone/fcmToken.
await check("Mallory ΔΕΝ γράφει email στο δικό της δημόσιο doc (PII lockdown)", () =>
  assertFails(updateDoc(doc(mallory, "users", MALLORY), { email: "m@x.com" })));
await check("Mallory ΔΕΝ γράφει phone στο δικό της δημόσιο doc (PII lockdown)", () =>
  assertFails(updateDoc(doc(mallory, "users", MALLORY), { phone: "+306999999999" })));
await check("Mallory ΔΕΝ γράφει fcmToken στο δικό της δημόσιο doc (PII lockdown)", () =>
  assertFails(updateDoc(doc(mallory, "users", MALLORY), { fcmToken: "leak" })));

await check("#2 Mallory ΔΕΝ φτιάχνει notification (phishing push)", () =>
  assertFails(addDoc(collection(mallory, "notifications"),
    { targetUid: BOB, title: "Το deal ακυρώθηκε", body: "πάτα εδώ" })));

await check("#3 Alice ΔΕΝ προσθέτει τρίτον στο chat (διαρροή ιστορικού)", () =>
  assertFails(updateDoc(doc(alice, "chats", "chatAB"),
    { participants: [ALICE, BOB, MALLORY] })));

await check("#4 Alice ΔΕΝ σβήνει μήνυμα του Bob", () =>
  assertFails(deleteDoc(doc(alice, "chats", "chatAB", "messages", "mB"))));

await check("#5 Mallory ΔΕΝ αυτοπροστίθεται στους φίλους της Alice", () =>
  assertFails(updateDoc(doc(mallory, "users", ALICE), { friends: arrayUnion(MALLORY) })));

await check("#5 Mallory ΔΕΝ σβήνει τους φίλους της Alice", () =>
  assertFails(updateDoc(doc(mallory, "users", ALICE), { friends: [] })));

await check("#6 Mallory ΔΕΝ διαβάζει ξένο deal", () =>
  assertFails(getDoc(doc(mallory, "deals", "dealAB"))));

await check("#6 Query deals χωρίς περιορισμό συμμετέχοντα απορρίπτεται", () =>
  assertFails(getDocs(query(collection(mallory, "deals"),
    where("chatId", "==", "chatAB")))));

await check("#7 Mallory ΔΕΝ φτιάχνει chat μεταξύ τρίτων", () =>
  assertFails(addDoc(collection(mallory, "chats"), { participants: [ALICE, BOB] })));

await check("#7 Mallory ΔΕΝ φτιάχνει deal μεταξύ τρίτων", () =>
  assertFails(addDoc(collection(mallory, "deals"), {
    participants: [ALICE, BOB], user1Uid: ALICE, user2Uid: BOB, status: "pending",
  })));

await check("#8 Mallory ΔΕΝ χειραγωγεί trending tag count", () =>
  assertFails(updateDoc(doc(mallory, "tags", "sport"), { count: 9999 })));

await check("#8 Mallory ΔΕΝ σβήνει tag", () =>
  assertFails(deleteDoc(doc(mallory, "tags", "sport"))));

await check("Mallory ΔΕΝ σβήνει τα likes άλλων σε post", () =>
  assertFails(updateDoc(doc(mallory, "wallPosts", "wp1"), { likes: [] })));

await check("Mallory ΔΕΝ ανεβάζει το rating της", () =>
  assertFails(updateDoc(doc(mallory, "users", MALLORY), { rating: 5, ratingCount: 99 })));

// ── DEAL RATING FARMING ──────────────────────────────────────────────────
await check("Alice ΔΕΝ βαθμολογεί τον εαυτό της (γράφει seekerRating αντί owner)", () =>
  assertFails(updateDoc(doc(alice, "deals", "dealDone"), { seekerRating: 5 })));

await check("Bob ΔΕΝ βαθμολογεί τον εαυτό του (γράφει ownerRating αντί seeker)", () =>
  assertFails(updateDoc(doc(bob, "deals", "dealDone"), { ownerRating: 5 })));

await check("ΔΕΝ γράφεται αυθαίρετη τιμή rating (1000000)", () =>
  assertFails(updateDoc(doc(alice, "deals", "dealDone"), { ownerRating: 1000000 })));

await check("ΔΕΝ γράφεται rating εκτός 1–5 (0)", () =>
  assertFails(updateDoc(doc(alice, "deals", "dealDone"), { ownerRating: 0 })));

await check("ΔΕΝ γράφεται double εκτός ορίων (1000000.5)", () =>
  assertFails(updateDoc(doc(alice, "deals", "dealDone"), { ownerRating: 1000000.5 })));

await check("ΔΕΝ βαθμολογείται deal που ΔΕΝ είναι completed", () =>
  assertFails(updateDoc(doc(alice, "deals", "dealAB"), { ownerRating: 5 })));

await check("Alice ΔΕΝ φτιάχνει deal με τον εαυτό της (self-deal)", () =>
  assertFails(addDoc(collection(alice, "deals"), {
    participants: [ALICE, ALICE], user1Uid: ALICE, user2Uid: ALICE, status: "pending",
  })));

await check("Ο client ΔΕΝ ολοκληρώνει μόνος του deal (status→completed)", () =>
  assertFails(updateDoc(doc(alice, "deals", "dealAB"), { status: "completed" })));

await check("Alice (αποστολέας) ΔΕΝ αποδέχεται μόνη της το αίτημα φιλίας", () =>
  assertFails(updateDoc(doc(alice, "friendRequests", "fr1"), { status: "accepted" })));

await check("Mallory ΔΕΝ διαβάζει μηνύματα ξένου chat", () =>
  assertFails(getDoc(doc(mallory, "chats", "chatAB", "messages", "mA"))));

await check("Alice ΔΕΝ ξεκρύβει αγγελία που κρύφτηκε από reports", () =>
  assertFails(updateDoc(doc(alice, "listings", "l1"), { isHidden: false, reportCount: 0 })));

await check("Mallory ΔΕΝ διαβάζει notification της Alice", () =>
  assertFails(getDoc(doc(mallory, "notifications", "n1"))));

await check("Mallory ΔΕΝ επεξεργάζεται ξένη αγγελία", () =>
  assertFails(updateDoc(doc(mallory, "listings", "l1"), { title: "hacked" })));

await check("Ο κάτοχος ΜΠΟΡΕΙ να επεξεργαστεί την αγγελία του (τίτλο)", () =>
  assertSucceeds(updateDoc(doc(alice, "listings", "l1"), { title: "νέος τίτλος" })));

await check("Ο συντάκτης ΔΕΝ ξεκρύβει post που κρύφτηκε από reports", () =>
  assertFails(updateDoc(doc(alice, "userPosts", "up_hidden"),
    { isHidden: false, reportCount: 0 })));

await check("Ο συντάκτης ΔΕΝ μηδενίζει το reportCount του post του", () =>
  assertFails(updateDoc(doc(alice, "userPosts", "up_hidden"), { reportCount: 0 })));

await check("Ο συντάκτης ΜΠΟΡΕΙ να επεξεργαστεί το κείμενο του post του", () =>
  assertSucceeds(updateDoc(doc(alice, "userPosts", "up_hidden"), { text: "νέο κείμενο" })));

await check("Υποβολή αναφοράς σε post ξένου χρήστη", () =>
  assertSucceeds(addDoc(collection(mallory, "reports"), {
    reporterUid: MALLORY, targetUid: ALICE,
    postCollection: "userPosts", postId: "up_hidden", reason: "spam",
  })));

await check("Dedup query αναφορών (reporterUid + targetUid + postId)", () =>
  assertSucceeds(getDocs(query(collection(mallory, "reports"),
    where("reporterUid", "==", MALLORY), where("targetUid", "==", ALICE),
    where("postId", "==", "up_hidden")))));

await check("Δεν διαβάζω τις αναφορές ΑΛΛΩΝ", () =>
  assertFails(getDocs(query(collection(mallory, "reports"),
    where("reporterUid", "==", ALICE)))));

console.log(results.join("\n"));
results.length = 0;

console.log("\n🟢 ΚΑΝΟΝΙΚΗ ΛΕΙΤΟΥΡΓΙΑ (πρέπει να ΔΟΥΛΕΥΕΙ)");

await check("Βλέπω το δικό μου email/τηλέφωνο", () =>
  assertSucceeds(getDoc(doc(alice, "users", ALICE, "private", "data"))));

await check("Αποθηκεύω FCM token / γλώσσα στο private doc", () =>
  assertSucceeds(setDoc(doc(alice, "users", ALICE, "private", "data"),
    { fcmToken: "new", language: "el" }, { merge: true })));

await check("Αλλάζω το κινητό μου (private) + σημαίες επαλήθευσης", async () => {
  await assertSucceeds(setDoc(doc(alice, "users", ALICE, "private", "data"),
    { phone: "+306900000000" }, { merge: true }));
  await assertSucceeds(updateDoc(doc(alice, "users", ALICE),
    { phoneVerified: true, isVerified: true }));
});

await check("Δημόσιο προφίλ άλλου = ορατό (search/inbox/αγγελίες)", () =>
  assertSucceeds(getDoc(doc(mallory, "users", ALICE))));

await check("Επεξεργασία προφίλ (όνομα, online status)", () =>
  assertSucceeds(updateDoc(doc(alice, "users", ALICE),
    { firstName: "Alice", lastName: "K", showOnlineStatus: false })));

await check("Αποθήκευση αγγελίας / block χρήστη", async () => {
  await assertSucceeds(updateDoc(doc(alice, "users", ALICE),
    { savedListingIds: arrayUnion("l1") }));
  await assertSucceeds(updateDoc(doc(alice, "users", ALICE),
    { blockedUids: arrayUnion(MALLORY) }));
  await assertSucceeds(updateDoc(doc(alice, "users", ALICE),
    { blockedUids: arrayRemove(MALLORY) }));
});

await check("Νέος χρήστης φτιάχνει το προφίλ του", () =>
  assertSucceeds(setDoc(doc(env.authenticatedContext("newbie").firestore(), "users", "newbie"),
    { uid: "newbie", firstName: "N", lastName: "B", rating: 0.0, ratingCount: 0,
      friends: [], dealsCount: 0, blockedUids: [], savedListingIds: [] })));

await check("Δημιουργία chat (είμαι μέσα, 2 άτομα)", () =>
  assertSucceeds(addDoc(collection(alice, "chats"),
    { participants: [ALICE, MALLORY], lastMessage: "", unread: false })));

await check("Αποστολή μηνύματος", () =>
  assertSucceeds(addDoc(collection(alice, "chats", "chatAB", "messages"),
    { senderId: ALICE, text: "γεια", messageType: "text" })));

await check("Ενημέρωση chat (lastMessage/unread/typing/mute)", async () => {
  await assertSucceeds(updateDoc(doc(alice, "chats", "chatAB"),
    { lastMessage: "γεια", lastSenderId: ALICE, unread: true }));
  await assertSucceeds(updateDoc(doc(bob, "chats", "chatAB"), { unread: false }));
  await assertSucceeds(updateDoc(doc(alice, "chats", "chatAB"),
    { typingUids: arrayUnion(ALICE) }));
  await assertSucceeds(updateDoc(doc(bob, "chats", "chatAB"),
    { mutedBy: arrayUnion(BOB) }));
});

await check("Read receipt + reaction στο μήνυμα του άλλου", async () => {
  await assertSucceeds(updateDoc(doc(bob, "chats", "chatAB", "messages", "mA"),
    { readBy: arrayUnion(BOB) }));
  await assertSucceeds(updateDoc(doc(bob, "chats", "chatAB", "messages", "mA"),
    { [`reactions.${BOB}`]: "❤️" }));
});

await check("Edit δικού μου μηνύματος", () =>
  assertSucceeds(updateDoc(doc(alice, "chats", "chatAB", "messages", "mA"),
    { text: "διορθωμένο", editedAt: serverTimestamp() })));

await check("Inbox query (chats μου)", () =>
  assertSucceeds(getDocs(query(collection(alice, "chats"),
    where("participants", "array-contains", ALICE)))));

await check("Deals μου (array-contains + orderBy)", () =>
  assertSucceeds(getDocs(query(collection(alice, "deals"),
    where("participants", "array-contains", ALICE), orderBy("createdAt", "desc")))));

await check("Deal του chat (chatId + participants)", () =>
  assertSucceeds(getDocs(query(collection(alice, "deals"),
    where("chatId", "==", "chatAB"), where("participants", "array-contains", ALICE)))));

// ΑΚΡΙΒΩΣ το payload που στέλνει ο client (deal_repository.createDeal) — μαζί με
// τα `ownerRating: null` / `seekerRating: null`. Το παλιό test τα παρέλειπε, γι'
// αυτό δεν έπιασε ότι ένας κανόνας με `keys().hasAny([...])` μπλόκαρε ΚΑΘΕ
// δημιουργία deal (permission-denied στην πραγματική εφαρμογή).
await check("Δημιουργία deal (πραγματικό payload client, με null ratings)", () =>
  assertSucceeds(addDoc(collection(alice, "deals"), {
    chatId: "chatAB", listingId: "l1", listingTitle: "T",
    participants: [ALICE, BOB], user1Uid: ALICE, user2Uid: BOB,
    proposerUid: ALICE, status: "pending",
    proposal1: null, proposal2: null, activatedAt: null,
    startDate: null, endDate: null,
    ownerRating: null, seekerRating: null,
    createdAt: serverTimestamp(),
  })));

await check("Δημιουργία deal ΜΕ φυτεμένο rating απορρίπτεται", () =>
  assertFails(addDoc(collection(alice, "deals"), {
    chatId: "chatAB", participants: [ALICE, BOB], user1Uid: ALICE, user2Uid: BOB,
    proposerUid: ALICE, status: "pending", ownerRating: 5,
    createdAt: serverTimestamp(),
  })));

await check("Πρόταση + αποδοχή deal, ακύρωση pending", async () => {
  await assertSucceeds(updateDoc(doc(alice, "deals", "dealAB"),
    { proposal1: { title: "x" }, status: "pending" }));
  await assertSucceeds(updateDoc(doc(bob, "deals", "dealAB"),
    { status: "active", startDate: new Date(), endDate: new Date() }));
});

await check("Ακύρωση ΜΗ-pending deal απορρίπτεται (deal είναι active)", () =>
  assertFails(updateDoc(doc(alice, "deals", "dealAB"), { status: "cancelled" })));

await check("Νόμιμη αξιολόγηση: user1 βαθμολογεί (ownerRating 1–5) completed deal", () =>
  assertSucceeds(updateDoc(doc(alice, "deals", "dealDone"), { ownerRating: 5 })));

// ΣΚΟΠΙΜΑ double (4.5): ο Dart client στέλνει `double rating` (deal_repository),
// που το Firestore αποθηκεύει ως double. Ένα `v is int` στα rules απέρριπτε ΚΑΘΕ
// αξιολόγηση της πραγματικής εφαρμογής με permission-denied.
await check("Νόμιμη αξιολόγηση: user2 βαθμολογεί με DOUBLE (όπως ο Dart client)", () =>
  assertSucceeds(updateDoc(doc(bob, "deals", "dealDone"), { seekerRating: 4.5 })));

await check("Ο παραλήπτης αποδέχεται αίτημα φιλίας", () =>
  assertSucceeds(updateDoc(doc(bob, "friendRequests", "fr1"),
    { status: "accepted", respondedAt: serverTimestamp() })));

await check("Αποστολή αιτήματος φιλίας", () =>
  assertSucceeds(addDoc(collection(alice, "friendRequests"),
    { fromUid: ALICE, toUid: MALLORY, status: "pending" })));

await check("Like σε post (μόνο το δικό μου) + μετρητής σχολίων ±1", async () => {
  await assertSucceeds(updateDoc(doc(mallory, "wallPosts", "wp1"),
    { likes: arrayUnion(MALLORY) }));
  await assertSucceeds(updateDoc(doc(mallory, "wallPosts", "wp1"),
    { likes: arrayRemove(MALLORY) }));
  await assertSucceeds(updateDoc(doc(mallory, "wallPosts", "wp1"),
    { commentsCount: increment(1) }));
  await assertSucceeds(updateDoc(doc(mallory, "wallPosts", "wp1"),
    { commentsCount: increment(-1) }));
});

await check("Trending tags: +1 και -1", async () => {
  await assertSucceeds(setDoc(doc(alice, "tags", "sport"),
    { name: "sport", count: increment(1), lastUsedAt: serverTimestamp() }, { merge: true }));
  await assertSucceeds(setDoc(doc(alice, "tags", "sport"),
    { count: increment(-1) }, { merge: true }));
  await assertSucceeds(setDoc(doc(alice, "tags", "νεο"),
    { name: "νεο", count: increment(1), lastUsedAt: serverTimestamp() }, { merge: true }));
});

await check("Διάβασμα/mark-read δικών μου notifications", async () => {
  await assertSucceeds(getDoc(doc(alice, "notifications", "n1")));
  await assertSucceeds(updateDoc(doc(alice, "notifications", "n1"), { isRead: true }));
});

await check("Υποβολή report", () =>
  assertSucceeds(addDoc(collection(alice, "reports"),
    { reporterUid: ALICE, targetUid: MALLORY, reason: "spam" })));

await check("Διαγραφή συνομιλίας: chat doc → μετά τα μηνύματα (ορφανά)", async () => {
  await assertSucceeds(deleteDoc(doc(alice, "chats", "chatAB")));
  await assertSucceeds(deleteDoc(doc(alice, "chats", "chatAB", "messages", "mA")));
  await assertSucceeds(deleteDoc(doc(alice, "chats", "chatAB", "messages", "mB")));
});

console.log("\n🗑️  ΔΙΑΓΡΑΦΗ ΜΗΝΥΜΑΤΩΝ & ΣΧΟΛΙΩΝ");

await check("Ο αποστολέας ΣΒΗΝΕΙ το δικό του μήνυμα (soft)", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "chats", "chatDel"), { participants: [ALICE, BOB] });
    await setDoc(doc(db, "chats", "chatDel", "messages", "mine"),
      { senderId: ALICE, text: "δικό μου" });
    await setDoc(doc(db, "chats", "chatDel", "messages", "theirs"),
      { senderId: BOB, text: "δικό του" });
  });
  await assertSucceeds(updateDoc(doc(alice, "chats", "chatDel", "messages", "mine"),
    { isDeleted: true, deletedAt: serverTimestamp(), text: "", mediaUrl: null }));
});

await check("Διαγραφή ΞΕΝΟΥ μηνύματος απορρίπτεται", () =>
  assertFails(updateDoc(doc(alice, "chats", "chatDel", "messages", "theirs"),
    { isDeleted: true, deletedAt: serverTimestamp(), text: "" })));

await check("«Ξε-διαγραφή» απορρίπτεται (επαναφορά περιεχομένου)", () =>
  assertFails(updateDoc(doc(alice, "chats", "chatDel", "messages", "mine"),
    { isDeleted: false, text: "επαναφορά" })));

await check("Ο συντάκτης σβήνει το σχόλιό του (soft)", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "userPosts", "up1"), { authorUid: BOB, commentsCount: 1, likes: [] });
    await setDoc(doc(db, "userPosts", "up1", "comments", "c1"),
      { authorUid: ALICE, text: "γεια", likes: [] });
  });
  await assertSucceeds(updateDoc(doc(alice, "userPosts", "up1", "comments", "c1"),
    { isDeleted: true, deletedAt: serverTimestamp(), text: "" }));
});

await check("ΞΕΝΟΣ δεν σβήνει το σχόλιό μου", async () => {
  // ΦΡΕΣΚΟ σχόλιο: αν χρησιμοποιούσαμε το ήδη διαγραμμένο c1, η εγγραφή θα
  // ήταν no-op (κενό diff) και θα περνούσε — το τεστ θα «πράσινιζε» χωρίς λόγο.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "userPosts", "up1", "comments", "c2"),
      { authorUid: ALICE, text: "ζωντανό σχόλιο", likes: [] });
  });
  await assertFails(updateDoc(doc(mallory, "userPosts", "up1", "comments", "c2"),
    { isDeleted: true, text: "" }));
});

console.log("\n↩️  ΑΚΥΡΩΣΗ ΑΙΤΗΜΑΤΟΣ ΦΙΛΙΑΣ");

await check("Ο ΑΠΟΣΤΟΛΕΑΣ ακυρώνει το δικό του pending αίτημα", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "friendRequests", "frCancel"),
      { fromUid: ALICE, toUid: BOB, status: "pending" });
  });
  await assertSucceeds(deleteDoc(doc(alice, "friendRequests", "frCancel")));
});

await check("Ο ΠΑΡΑΛΗΠΤΗΣ μπορεί επίσης να το απορρίψει/σβήσει", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "friendRequests", "frReject"),
      { fromUid: ALICE, toUid: BOB, status: "pending" });
  });
  await assertSucceeds(deleteDoc(doc(bob, "friendRequests", "frReject")));
});

await check("ΤΡΙΤΟΣ ΔΕΝ σβήνει ξένο αίτημα", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "friendRequests", "frOther"),
      { fromUid: ALICE, toUid: BOB, status: "pending" });
  });
  await assertFails(deleteDoc(doc(mallory, "friendRequests", "frOther")));
});

// ══════════════════════════════════════════════════════════════════════
// REGRESSION — security audit (Ιούλιος 2026)
// Κάθε test αντιστοιχεί σε ΠΡΑΓΜΑΤΙΚΗ ευπάθεια που βρέθηκε και διορθώθηκε.
// ══════════════════════════════════════════════════════════════════════
console.log("\n🛡️  REGRESSION — ευπάθειες που διορθώθηκαν");

await check("Ο client ΔΕΝ δημιουργεί wall post (φύτεμα ψεύτικου deal σε ξένο τοίχο)", () =>
  assertFails(addDoc(collection(mallory, "wallPosts"), {
    authorUid: MALLORY, targetUid: ALICE, type: "deal", status: "completed",
    dealStatus: "completed", title: "Deal ολοκληρώθηκε",
    details: "συκοφαντικό κείμενο", user1Uid: ALICE, user2Uid: MALLORY,
    createdAt: new Date(), likes: [], commentsCount: 0,
  })));

await check("Ο client ΔΕΝ δημιουργεί wall post ούτε στον ΔΙΚΟ του τοίχο (φούσκωμα φήμης)", () =>
  assertFails(addDoc(collection(mallory, "wallPosts"), {
    authorUid: MALLORY, targetUid: MALLORY, type: "deal", status: "completed",
    createdAt: new Date(),
  })));

await check("Η αγγελία ΔΕΝ αλλάζει ιδιοκτήτη (μεταβίβαση σε ανυποψίαστο θύμα)", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "listings", "lMal"),
      { userId: MALLORY, title: "παράνομο περιεχόμενο" });
  });
  await assertFails(updateDoc(doc(mallory, "listings", "lMal"), { userId: BOB }));
});

await check("Ο κάτοχος επεξεργάζεται κανονικά την αγγελία του (δεν σπάσαμε το edit)", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "listings", "lEdit"),
      { userId: MALLORY, title: "παλιός", description: "π" });
  });
  await assertSucceeds(updateDoc(doc(mallory, "listings", "lEdit"),
    { title: "νέος", description: "ν" }));
});

await check("Το user post ΔΕΝ αλλάζει συντάκτη", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "userPosts", "upMal"),
      { authorUid: MALLORY, text: "κακόβουλο", likes: [] });
  });
  await assertFails(updateDoc(doc(mallory, "userPosts", "upMal"), { authorUid: BOB }));
});

await check("Το σχόλιο ΔΕΝ αλλάζει συντάκτη", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "userPosts", "up1", "comments", "cMal"),
      { authorUid: MALLORY, text: "κακόβουλο", likes: [] });
  });
  await assertFails(updateDoc(doc(mallory, "userPosts", "up1", "comments", "cMal"),
    { authorUid: BOB }));
});

await check("Ο χρήστης ΔΕΝ ξαναγράφει το createdAt (πλαστή ηλικία λογαριασμού)", () =>
  assertFails(updateDoc(doc(mallory, "users", MALLORY),
    { createdAt: new Date("2019-01-01") })));

await check("Ο χρήστης ΔΕΝ ξαναγράφει το ageVerified/termsAcceptedAt (νομικό αρχείο)", () =>
  assertFails(updateDoc(doc(mallory, "users", MALLORY),
    { ageVerified: true, termsAcceptedAt: new Date("2030-01-01") })));

await check("Κανονική ενημέρωση προφίλ δουλεύει ακόμα (δεν σπάσαμε το edit profile)", () =>
  assertSucceeds(updateDoc(doc(mallory, "users", MALLORY),
    { firstName: "Νέο", lastName: "Όνομα" })));

await check("Ο ΠΡΟΤΕΙΝΩΝ (user1) ΔΕΝ αποδέχεται τη δική του πρόταση", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "deals", "dealSelf"), {
      chatId: "chatAB", participants: [ALICE, BOB],
      user1Uid: ALICE, user2Uid: BOB, status: "pending",
      proposal1: { userId: ALICE, accepted: true }, proposal2: null,
      ownerRating: null, seekerRating: null, createdAt: new Date(),
    });
  });
  // Η Alice είναι ο user1 (προτείνων) — δεν γίνεται να ενεργοποιήσει η ίδια.
  await assertFails(updateDoc(doc(alice, "deals", "dealSelf"),
    { status: "active", activatedAt: new Date() }));
});

await check("Ο ΠΑΡΑΛΗΠΤΗΣ (user2) αποδέχεται κανονικά (δεν σπάσαμε τη ροή)", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "deals", "dealOk"), {
      chatId: "chatAB", participants: [ALICE, BOB],
      user1Uid: ALICE, user2Uid: BOB, status: "pending",
      proposal1: { userId: ALICE, accepted: true }, proposal2: null,
      ownerRating: null, seekerRating: null, createdAt: new Date(),
    });
  });
  await assertSucceeds(updateDoc(doc(bob, "deals", "dealOk"), {
    status: "active", activatedAt: new Date(),
    startDate: new Date(), endDate: new Date(Date.now() + 86400000),
  }));
});

await check("Ο user1 ενημερώνει ΑΛΛΑ πεδία ενεργού deal (δεν κλειδώθηκε έξω)", () =>
  assertSucceeds(updateDoc(doc(alice, "deals", "dealOk"),
    { proposal1: { userId: ALICE, accepted: true, note: "ok" } })));

// ΔΙΚΟ ΤΟΥΣ chat: το `chatAB` έχει ήδη διαγραφεί από το test «Διαγραφή
// συνομιλίας» παραπάνω. Χωρίς φρέσκο doc, το assertFails θα περνούσε για ΛΑΘΟΣ
// λόγο (ανύπαρκτο έγγραφο) και δεν θα έλεγχε τίποτα.
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), "chats", "chatPreview"), {
    participants: [ALICE, BOB], lastMessage: "hi",
    lastSenderId: ALICE, unread: false,
  });
});

await check("Ψεύτικη προεπισκόπηση inbox στο όνομα του άλλου απορρίπτεται (phishing)", () =>
  assertFails(updateDoc(doc(bob, "chats", "chatPreview"), {
    lastMessage: "Ο λογαριασμός σου κλειδώθηκε — πάτα εδώ",
    lastSenderId: ALICE,
  })));

await check("Ψεύτικη προεπισκόπηση ΧΩΡΙΣ αλλαγή lastSenderId απορρίπτεται", () =>
  assertFails(updateDoc(doc(bob, "chats", "chatPreview"),
    { lastMessage: "Πάτα εδώ για να ξεκλειδώσεις" })));

await check("Κανονική αποστολή ενημερώνει την προεπισκόπηση (δεν σπάσαμε το chat)", () =>
  assertSucceeds(updateDoc(doc(bob, "chats", "chatPreview"),
    { lastMessage: "γεια", lastSenderId: BOB, unread: true })));

await check("Το mark-as-read δεν επηρεάζεται από τον νέο κανόνα", () =>
  assertSucceeds(updateDoc(doc(alice, "chats", "chatPreview"), { unread: false })));

console.log(results.join("\n"));
console.log(`\n${"─".repeat(60)}\nΣΥΝΟΛΟ: ${pass} πέρασαν, ${fail} απέτυχαν\n`);
await env.cleanup();
process.exit(fail > 0 ? 1 : 0);
