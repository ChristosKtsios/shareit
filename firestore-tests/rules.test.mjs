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

const alice = env.authenticatedContext(ALICE).firestore();
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
      dealsCount: 0, friends: [], blockedUids: [], savedListingIds: [],
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

await check("#1 Mallory ΔΕΝ γράφει email/phone στο δημόσιο doc της (re-leak)", () =>
  assertFails(updateDoc(doc(mallory, "users", MALLORY), { email: "m@x.com" })));

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

await check("Δημιουργία deal (είμαι συμμετέχων)", () =>
  assertSucceeds(addDoc(collection(alice, "deals"), {
    chatId: "chatAB", participants: [ALICE, BOB], user1Uid: ALICE, user2Uid: BOB,
    proposerUid: ALICE, status: "pending", createdAt: serverTimestamp(),
  })));

await check("Πρόταση + αποδοχή deal, ακύρωση pending", async () => {
  await assertSucceeds(updateDoc(doc(alice, "deals", "dealAB"),
    { proposal1: { title: "x" }, status: "pending" }));
  await assertSucceeds(updateDoc(doc(bob, "deals", "dealAB"),
    { status: "active", startDate: new Date(), endDate: new Date() }));
});

await check("Ακύρωση ΜΗ-pending deal απορρίπτεται (deal είναι active)", () =>
  assertFails(updateDoc(doc(alice, "deals", "dealAB"), { status: "cancelled" })));

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

console.log(results.join("\n"));
console.log(`\n${"─".repeat(60)}\nΣΥΝΟΛΟ: ${pass} πέρασαν, ${fail} απέτυχαν\n`);
await env.cleanup();
process.exit(fail > 0 ? 1 : 0);
