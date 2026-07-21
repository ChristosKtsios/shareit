/**
 * reindex-search.mjs — ξαναγράφει τα `searchKeywords` ΟΛΩΝ των αγγελιών.
 *
 * ΓΙΑΤΙ: η αναζήτηση πλέον κάνει fold τόνων (τρυπάνι → τρυπανι) και ψάχνει
 * λέξη-λέξη. Οι ΠΑΛΙΕΣ αγγελίες έχουν keywords ΜΕ τόνους, οπότε δεν θα
 * ταίριαζαν ποτέ. Αυτό το script τα ξαναχτίζει με τη νέα μορφή.
 *
 * ΠΡΕΠΕΙ να τρέξει μία φορά μετά το deploy της νέας έκδοσης.
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/serviceAccount.json
 *   node reindex-search.mjs           → DRY RUN (δείχνει τι θα άλλαζε)
 *   node reindex-search.mjs --write   → γράφει
 *
 * Η λογική ΠΡΕΠΕΙ να είναι πανομοιότυπη με το Dart:
 *   lib/core/utils/greek_text.dart  → GreekText.fold
 *   lib/features/listings/data/listing_model.dart → ListingModel.tokenize
 */
import admin from 'firebase-admin';

admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();
const WRITE = process.argv.includes('--write');

// --- ΚΑΤΟΠΤΡΟ του GreekText.fold (Dart) ---
const FOLD = {
  'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω',
  'ϊ': 'ι', 'ϋ': 'υ', 'ΐ': 'ι', 'ΰ': 'υ', 'ς': 'σ',
};
const fold = (s) => s.toLowerCase().split('').map((c) => FOLD[c] ?? c).join('');

// --- ΚΑΤΟΠΤΡΟ του ListingModel._words (Dart) ---
const words = (text, doFold) => [...new Set(
  (doFold ? fold(text) : text.toLowerCase())
    .replace(/[^\w\sα-ωάέήίόύώϊϋΐΰ]/gu, ' ')
    .split(/\s+/)
    .filter((w) => w.length > 2)
)];

// --- ΚΑΤΟΠΤΡΟ του ListingModel._prefixes (Dart) ---
// --- ΚΑΤΟΠΤΡΟ του GreekText.greeklishVariants (Dart) ---
// ΔΥΟ παραλλαγές: τα greeklish δεν γράφονται με έναν τρόπο.
//   Α «φωνητική»: μπ→b,  ντ→d,  χ→ch, υ→y, ω→o, η→i   («paichnidi», «bala»)
//   Β «οπτική»:   μπ→mp, ντ→nt, χ→x,  υ→i, ω→w, η→h   («paixnidi», «mpala»)
const DI_A = {
  'ου': 'ou', 'αι': 'ai', 'ει': 'ei', 'οι': 'oi', 'αυ': 'af', 'ευ': 'ef',
  'γγ': 'ng', 'γκ': 'gk', 'μπ': 'b', 'ντ': 'd', 'τσ': 'ts', 'τζ': 'tz',
};
const LE_A = {
  'α': 'a', 'β': 'v', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'i',
  'θ': 'th', 'ι': 'i', 'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'x',
  'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's', 'τ': 't', 'υ': 'y', 'φ': 'f',
  'χ': 'ch', 'ψ': 'ps', 'ω': 'o',
};
const DI_B = {
  'ου': 'ou', 'γγ': 'gg', 'γκ': 'gk', 'μπ': 'mp', 'ντ': 'nt',
  'τσ': 'ts', 'τζ': 'tz',
};
const LE_B = {
  'α': 'a', 'β': 'b', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'h',
  'θ': 'th', 'ι': 'i', 'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'ks',
  'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's', 'τ': 't', 'υ': 'i', 'φ': 'f',
  'χ': 'x', 'ψ': 'ps', 'ω': 'w',
};
const HAS_GREEK = /[α-ωΑ-Ωά-ώΆ-Ώ]/;
const mapGl = (s, di, le) => {
  let t = fold(s);
  for (const [k, v] of Object.entries(di)) t = t.split(k).join(v);
  return t.split('').map((c) => le[c] ?? c).join('');
};
const greeklishVariants = (s) => {
  if (!HAS_GREEK.test(s)) return [];
  return [...new Set([mapGl(s, DI_A, LE_A), mapGl(s, DI_B, LE_B)])]
    .filter((w) => w.length >= 3);
};

const MIN_PREFIX = 3;
const prefixes = (w) => {
  const out = [];
  for (let i = MIN_PREFIX; i <= w.length; i++) out.push(w.slice(0, i));
  return out;
};

// --- ΚΑΤΟΠΤΡΟ του ListingModel.generateKeywords (Dart) ---
// Άτονα (νέα αναζήτηση) + τονισμένα (συμβατότητα με την ΠΑΛΙΑ έκδοση της app,
// που ψάχνει με arrayContains στην τονισμένη λέξη). Μη βγάλεις τα τονισμένα:
// θα σπάσει η αναζήτηση σε όποιον δεν έχει ενημερωθεί.
// Προθέματα ΜΟΝΟ από τον τίτλο (βλ. σχόλιο στο Dart).
const tokenize = (text, title = '') => {
  const folded = words(text, true);
  const out = new Set([...folded, ...words(text, false)]);
  // GREEKLISH: «μικρόφωνο» → «mikrofono»/«mikrofwno», ώστε η αναζήτηση με
  // λατινικούς χαρακτήρες να βρίσκει ελληνικές αγγελίες.
  for (const w of folded) for (const gl of greeklishVariants(w)) out.add(gl);
  for (const w of words(title, true)) {
    for (const p of prefixes(w)) out.add(p);
    for (const gl of greeklishVariants(w)) {
      if (gl.length >= MIN_PREFIX) for (const p of prefixes(gl)) out.add(p);
    }
  }
  return [...out];
};

const same = (a, b) =>
  a.length === b.length && [...a].sort().join('|') === [...b].sort().join('|');

(async () => {
  const snap = await db.collection('listings').get();
  console.log(`🔎 ${snap.size} αγγελίες\n`);

  let changed = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    // Ίδιο input με ListingModel.generateKeywords: τίτλος + περιγραφή + τοποθεσία + tags
    const tags = Array.isArray(d.tags) ? d.tags.join(' ') : '';
    const next = tokenize(
      `${d.title ?? ''} ${d.description ?? ''} ${d.locationLabel ?? ''} ${tags}`,
      d.title ?? ''
    );
    const prev = Array.isArray(d.searchKeywords) ? d.searchKeywords : [];
    if (same(prev, next)) continue;

    changed++;
    console.log(`• ${d.title ?? '(χωρίς τίτλο)'}`);
    console.log(`    πριν : ${prev.join(', ') || '—'}`);
    console.log(`    μετά : ${next.join(', ')}`);
    if (WRITE) await doc.ref.update({ searchKeywords: next });
  }

  if (changed === 0) { console.log('✅ Όλα ήδη ενημερωμένα.'); }
  else if (WRITE)    { console.log(`\n✅ Ενημερώθηκαν ${changed} αγγελίες.`); }
  else               { console.log(`\nℹ️  DRY RUN — ${changed} θα άλλαζαν. Γράψε: node reindex-search.mjs --write`); }
  process.exit(0);
})();
