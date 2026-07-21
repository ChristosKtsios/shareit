import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { doc, setDoc, updateDoc } from "firebase/firestore";

const env = await initializeTestEnvironment({
  projectId: "demo-phone",
  firestore: { host: "127.0.0.1", port: 8098 },
});

// Χρήστης που ΠΕΡΑΣΕ OTP → το token του έχει claim `phone_number`.
const verified = env.authenticatedContext("u1", { phone_number: "+306900000000" }).firestore();
// Χρήστης χωρίς OTP (π.χ. Google sign-in) → ΔΕΝ έχει το claim.
const noOtp = env.authenticatedContext("u2").firestore();

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const uid of ["u1", "u2"]) {
    await setDoc(doc(db, "users", uid), { uid, firstName: "T", phoneVerified: false });
  }
});

let pass = 0, fail = 0;
const check = async (name, fn) => {
  try { await fn(); pass++; console.log("  ✅ " + name); }
  catch (e) { fail++; console.log("  ❌ " + name + "\n       " + String(e).split("\n")[0].slice(0,120)); }
};

console.log("\n🔴 ΕΠΙΘΕΣΗ");
await check("Χωρίς OTP ΔΕΝ δηλώνεται «επαληθευμένος»", () =>
  assertFails(updateDoc(doc(noOtp, "users", "u2"), { phoneVerified: true })));
await check("Χωρίς OTP ΔΕΝ δημιουργεί προφίλ με phoneVerified:true", () =>
  assertFails(setDoc(doc(noOtp, "users", "u3"), { uid: "u3", phoneVerified: true })));

console.log("\n🟢 ΚΑΝΟΝΙΚΗ ΛΕΙΤΟΥΡΓΙΑ");
await check("Μετά από OTP, δηλώνεται επαληθευμένος", () =>
  assertSucceeds(updateDoc(doc(verified, "users", "u1"), { phoneVerified: true, isVerified: true })));
await check("Χωρίς OTP, άλλες αλλαγές προφίλ δουλεύουν κανονικά", () =>
  assertSucceeds(updateDoc(doc(noOtp, "users", "u2"), { firstName: "Νέο όνομα" })));

// ── ΑΝΤΙ-LOCKOUT ────────────────────────────────────────────────────────────
// Ο χρήστης έχει ΗΔΗ phoneVerified:true στο doc του, αλλά το token του (για
// οποιονδήποτε λόγο) ΔΕΝ έχει το claim. Κάθε άσχετη αλλαγή στο προφίλ του
// ΠΡΕΠΕΙ να δουλεύει — αλλιώς κλειδώνεται μόνιμα έξω από το προφίλ του.
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), "users", "u4"),
    { uid: "u4", firstName: "V", phoneVerified: true });
});
const verifiedNoClaim = env.authenticatedContext("u4").firestore();

await check("Ήδη επαληθευμένος (χωρίς claim) αλλάζει όνομα — ΔΕΝ κλειδώνεται", () =>
  assertSucceeds(updateDoc(doc(verifiedNoClaim, "users", "u4"),
    { firstName: "Άλλο όνομα" })));
await check("Ήδη επαληθευμένος (χωρίς claim) μπλοκάρει χρήστη — ΔΕΝ κλειδώνεται", () =>
  assertSucceeds(updateDoc(doc(verifiedNoClaim, "users", "u4"),
    { blockedUids: ["x"] })));
// Η ασφάλεια κρατάει: η ΜΕΤΑΒΑΣΗ false → true χωρίς claim απορρίπτεται.
// (Το να ξαναγράψεις `true` πάνω σε ήδη `true` δεν αλλάζει τιμή — no-op, ακίνδυνο.)
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), "users", "u5"),
    { uid: "u5", firstName: "N", phoneVerified: false });
});
const notVerified = env.authenticatedContext("u5").firestore();
await check("Μετάβαση false→true ΧΩΡΙΣ claim απορρίπτεται (ασφάλεια κρατάει)", () =>
  assertFails(updateDoc(doc(notVerified, "users", "u5"),
    { phoneVerified: true, firstName: "Χ" })));

console.log(`\nΣΥΝΟΛΟ: ${pass} πέρασαν, ${fail} απέτυχαν\n`);
await env.cleanup();
process.exit(fail > 0 ? 1 : 0);
