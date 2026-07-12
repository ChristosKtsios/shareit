import { initializeTestEnvironment, assertSucceeds } from "@firebase/rules-unit-testing";
import { doc, setDoc, getDoc, serverTimestamp } from "firebase/firestore";

const env = await initializeTestEnvironment({
  projectId: "demo-google",
  firestore: { host: "127.0.0.1", port: 8098 },
});

let pass = 0, fail = 0;
const check = async (name, fn) => {
  try { await fn(); pass++; console.log("  ✅ " + name); }
  catch (e) { fail++; console.log("  ❌ " + name + "\n       " + String(e).split("\n")[0].slice(0,150)); }
};

const u1 = env.authenticatedContext("newGoogleUser1").firestore();
const u2 = env.authenticatedContext("newGoogleUser2").firestore();
const u3 = env.authenticatedContext("existingGoogle").firestore();

console.log("\n=== ΠΑΛΙΑ ΕΚΔΟΣΗ 1.0.2 (login_screen.dart:333-353) ===");
await check("Δημιουργία προφίλ Google — ΜΕ email/phone στο δημόσιο doc", () =>
  assertSucceeds(setDoc(doc(u1, "users", "newGoogleUser1"), {
    uid: "newGoogleUser1",
    firstName: "Test", lastName: "User",
    email: "test@gmail.com",          // ← η παλιά έκδοση τα γράφει εδώ
    phone: "",
    photoUrl: "https://x/p.jpg", avatarUrl: "https://x/p.jpg",
    rating: 0.0, ratingCount: 0,
    isVerified: true, phoneVerified: false,
    blockedUids: [], savedListingIds: [], friends: [],
    dealsCount: 0, isPrivateProfile: false, showOnlineStatus: true,
    termsAcceptedAt: serverTimestamp(), createdAt: serverTimestamp(),
  })));

console.log("\n=== ΝΕΑ ΕΚΔΟΣΗ 1.0.3 ===");
await check("Δημιουργία προφίλ Google — ΧΩΡΙΣ email/phone", () =>
  assertSucceeds(setDoc(doc(u2, "users", "newGoogleUser2"), {
    uid: "newGoogleUser2",
    firstName: "Test", lastName: "User",
    photoUrl: "https://x/p.jpg", avatarUrl: "https://x/p.jpg",
    rating: 0.0, ratingCount: 0,
    isVerified: true, phoneVerified: false,
    blockedUids: [], savedListingIds: [], friends: [],
    dealsCount: 0, isPrivateProfile: false, showOnlineStatus: true,
    termsAcceptedAt: serverTimestamp(), createdAt: serverTimestamp(),
  })));
await check("Γράφει email/phone στο private doc", () =>
  assertSucceeds(setDoc(doc(u2, "users", "newGoogleUser2", "private", "data"),
    { email: "t@gmail.com", phone: "" }, { merge: true })));

console.log("\n=== ΥΠΑΡΧΩΝ χρήστης ξανακάνει Google sign-in ===");
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), "users", "existingGoogle"),
    { uid: "existingGoogle", firstName: "", lastName: "", rating: 0, friends: [] });
});
await check("Παλιά έκδοση: συμπλήρωση ονόματος + email (merge)", () =>
  assertSucceeds(setDoc(doc(u3, "users", "existingGoogle"),
    { firstName: "A", lastName: "B", email: "a@gmail.com" }, { merge: true })));
await check("Νέα έκδοση: συμπλήρωση ονόματος (merge)", () =>
  assertSucceeds(setDoc(doc(u3, "users", "existingGoogle"),
    { firstName: "A", lastName: "B" }, { merge: true })));
await check("Ανάγνωση του δικού μου doc (ProfileGate)", () =>
  assertSucceeds(getDoc(doc(u3, "users", "existingGoogle"))));

console.log(`\nΣΥΝΟΛΟ: ${pass} πέρασαν, ${fail} απέτυχαν\n`);
await env.cleanup();
process.exit(fail > 0 ? 1 : 0);
