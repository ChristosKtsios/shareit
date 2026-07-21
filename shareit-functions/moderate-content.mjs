/**
 * moderate-content.mjs — σαρωτής/καθαριστής ακατάλληλου περιεχομένου.
 *
 * Σαρώνει listings / userPosts / wallPosts για ύποπτο κείμενο και:
 *   - ΧΩΡΙΣ flag  → DRY RUN: τυπώνει τι ΘΑ έσβηνε (δεν σβήνει τίποτα).
 *   - με --delete → σβήνει ΜΟΝΟ όσα εμφανίστηκαν στο dry run.
 *
 * ── ΠΩΣ ΤΡΕΧΕΙ ────────────────────────────────────────────────────────────
 *   1. Firebase Console → ⚙ Project settings → Service accounts
 *      → «Generate new private key» → κατέβασε το .json (ΜΗΝ το κάνεις commit).
 *   2. Από τον φάκελο shareit-functions/ :
 *        export GOOGLE_APPLICATION_CREDENTIALS=/απόλυτη/διαδρομή/serviceAccount.json
 *        node moderate-content.mjs            # δες τη λίστα (ασφαλές)
 *        node moderate-content.mjs --delete   # σβήσε αφού την ελέγξεις
 *
 *   Προαιρετικά:  --json  (πλήρες output),  --collection=listings  (μία μόνο)
 *
 * Το .json είναι ήδη στο .gitignore (service-account*.json). Σβήσ' το μετά.
 */

import admin from 'firebase-admin';

// ── ΛΕΞΕΙΣ-ΚΛΕΙΔΙΑ ─────────────────────────────────────────────────────────
// Επεξεργάσου ελεύθερα. Case-insensitive, πιάνει και τόνους/χωρίς τόνους.
// Στόχος: περιεχόμενο που αντιμετωπίζει ανθρώπους ως αντικείμενο, sexual/adult,
// και προφανές spam. ΔΕΝ σβήνει αυτόματα — απλώς επισημαίνει για έλεγχο.
const KEYWORDS = [
  'γυναικα', 'γυναίκα', 'γυναικες', 'γυναίκες',
  'κιλα', 'κιλά',
  'νυφη', 'νύφη', 'σεξ', 'sex', 'escort', 'πουτ', 'σκλαβ',
];

// Πεδία κειμένου ανά collection.
const TARGETS = {
  listings:  ['title', 'description'],
  userPosts: ['text'],
  wallPosts: ['text'],
};

// ── setup ─────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const DELETE = args.includes('--delete');
const AS_JSON = args.includes('--json');
const onlyCol = (args.find((a) => a.startsWith('--collection=')) || '').split('=')[1];

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('❌ Λείπει GOOGLE_APPLICATION_CREDENTIALS (δες οδηγίες στην κορυφή).');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();

// Χτίζει ένα regex που πιάνει τις λέξεις ανεξαρτήτως τόνου/κεφαλαίων.
const stripAccents = (s) =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const normalizedKeywords = KEYWORDS.map(stripAccents);

function matchedKeywords(text) {
  const hay = stripAccents(String(text || ''));
  return normalizedKeywords.filter((k) => hay.includes(k));
}

async function scanCollection(name, fields) {
  const snap = await db.collection(name).get();
  const flagged = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    const blob = fields.map((f) => data[f]).filter(Boolean).join('  ·  ');
    const hits = matchedKeywords(blob);
    if (hits.length > 0) {
      flagged.push({
        collection: name,
        id: doc.id,
        owner: data.userFirstName || data.authorName || data.userId || data.uid || '—',
        title: data.title || (blob.length > 80 ? blob.slice(0, 80) + '…' : blob),
        hits,
        ref: doc.ref,
      });
    }
  }
  return flagged;
}

(async () => {
  const cols = onlyCol ? { [onlyCol]: TARGETS[onlyCol] } : TARGETS;
  let all = [];
  for (const [name, fields] of Object.entries(cols)) {
    if (!fields) { console.warn(`⚠ άγνωστο collection: ${name}`); continue; }
    all = all.concat(await scanCollection(name, fields));
  }

  if (all.length === 0) {
    console.log('✅ Δεν βρέθηκε ύποπτο περιεχόμενο.');
    process.exit(0);
  }

  if (AS_JSON) {
    console.log(JSON.stringify(all.map(({ ref, ...r }) => r), null, 2));
  } else {
    console.log(`\n🔎 Βρέθηκαν ${all.length} ύποπτα:\n`);
    all.forEach((f, i) => {
      console.log(`${String(i + 1).padStart(2)}. [${f.collection}] ${f.title}`);
      console.log(`    owner: ${f.owner}   |   λέξεις: ${f.hits.join(', ')}`);
      console.log(`    id: ${f.id}\n`);
    });
  }

  if (!DELETE) {
    console.log('ℹ️  DRY RUN — δεν σβήστηκε τίποτα.');
    console.log('    Έλεγξε τη λίστα. Για διαγραφή: node moderate-content.mjs --delete\n');
    process.exit(0);
  }

  console.log(`🗑  Διαγραφή ${all.length} documents...`);
  let ok = 0;
  for (const f of all) {
    try { await f.ref.delete(); ok++; console.log(`   ✓ ${f.collection}/${f.id}`); }
    catch (e) { console.error(`   ✗ ${f.collection}/${f.id}: ${e.message}`); }
  }
  console.log(`\n✅ Διαγράφηκαν ${ok}/${all.length}.`);
  console.log('   Σημ.: οι εικόνες στο Storage μένουν ορφανές (μη προσβάσιμες χωρίς το doc).');
  process.exit(0);
})();
