/**
 * backfill-categories.mjs — γεμίζει το νέο πεδίο `category` σε αγγελίες που
 * δημιουργήθηκαν ΠΡΙΝ προστεθεί (δεν έχουν καθόλου το πεδίο).
 *
 * ΓΙΑΤΙ: μέχρι τώρα η μόνη ταξινόμηση ήταν ελεύθερα tags — «ρούχα»,
 * «clothes», «ένδυση» δεν συναντιούνταν ποτέ στο φίλτρο. Το `category` είναι
 * κλειστό σύνολο (βλ. ListingCategory στο lib/features/listings/data/
 * listing_model.dart) και είναι ΠΛΕΟΝ υποχρεωτικό στη δημιουργία/επεξεργασία
 * αγγελίας — αλλά οι παλιές αγγελίες δεν το έχουν.
 *
 * Η λογική είναι ΜΑΝΤΕΨΙΑ βάσει tags/τίτλου/περιγραφής (keyword matching) —
 * ΟΧΙ αλάνθαστη. Γι' αυτό ΠΑΝΤΑ dry-run πρώτα και έλεγξε το report πριν με
 * --write. Ό,τι δεν ταιριάξει με κανένα keyword πέφτει σε "other" — ασφαλές
 * fallback, ποτέ κενό πεδίο.
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/serviceAccount.json
 *   node backfill-categories.mjs           → DRY RUN (δείχνει τι θα άλλαζε)
 *   node backfill-categories.mjs --write   → γράφει
 *
 * Η λίστα κατηγοριών ΠΡΕΠΕΙ να μείνει ταυτόσημη με το Dart enum.
 */
import admin from 'firebase-admin';

admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();
const WRITE = process.argv.includes('--write');

// --- ΚΑΤΟΠΤΡΟ του GreekText.fold (Dart) — ίδιο με reindex-search.mjs ---
const FOLD = {
  'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω',
  'ϊ': 'ι', 'ϋ': 'υ', 'ΐ': 'ι', 'ΰ': 'υ', 'ς': 'σ',
};
const fold = (s) => s.toLowerCase().split('').map((c) => FOLD[c] ?? c).join('');

// Λέξεις-κλειδιά ανά κατηγορία (άτονες, πεζά — matching γίνεται σε folded
// κείμενο). Η σειρά μετράει: ελέγχονται με αυτή τη σειρά, η ΠΡΩΤΗ κατηγορία
// που ταιριάζει κερδίζει — γι' αυτό πιο συγκεκριμένες κατηγορίες (π.χ.
// «transport» πριν το γενικό «sports») μπαίνουν νωρίτερα.
const CATEGORY_KEYWORDS = [
  ['transport', [
    'ποδηλατ', 'ποδηλατο', 'μηχανακι', 'μοτοσικλετ', 'σκουτερ', 'πατινι',
    'trotinet', 'bicycle', 'bike',
  ]],
  ['electronics', [
    'τηλεφων', 'κινητο', 'tablet', 'laptop', 'υπολογιστ', 'ηλεκτρονικ',
    'τηλεορασ', 'κονσολ', 'playstation', 'xbox', 'ακουστικ', 'καμερ',
    'φορτιστ', 'καλωδι', 'router', 'modem', 'εκτυπωτ', 'ψυγει', 'πλυντηρι',
    'κλιματιστικ',
  ]],
  ['furniture', [
    'επιπλ', 'καρεκλ', 'τραπεζ', 'καναπ', 'κρεβατ', 'ντουλαπ', 'ραφι',
    'στρωμα', 'κομοδιν', 'furniture',
  ]],
  ['clothing', [
    'ρουχ', 'παπουτσ', 'παντελον', 'μπλουζ', 'φορεμ', 'ζακετ', 'μπουφαν',
    'παλτο', 'τσαντ', 'clothes', 'clothing',
  ]],
  ['books', [
    'βιβλι', 'περιοδικ', 'κομικ', 'εγκυκλοπ', 'book',
  ]],
  ['kids', [
    'παιδικ', 'παιχνιδ', 'βρεφικ', 'καροτσι', 'κουνι', 'kids', 'toy',
  ]],
  ['sports', [
    'αθλητικ', 'γυμναστικ', 'μπαλ', 'ρακετ', 'σκι', 'snowboard', 'sport',
    'βαρη', 'διαδρομ',
  ]],
  ['tools', [
    'εργαλει', 'τρυπανι', 'κατσαβιδ', 'πριον', 'σφυρι', 'πενσ', 'tool',
  ]],
  ['services', [
    'μαθηματ', 'μεταφορα', 'μετακομισ', 'καθαρισμ', 'επισκευ', 'μαθημ',
    'service',
  ]],
];

function guessCategory(listing) {
  const text = fold(
    `${listing.title || ''} ${listing.description || ''} ${(listing.tags || []).join(' ')}`,
  );
  for (const [category, keywords] of CATEGORY_KEYWORDS) {
    if (keywords.some((kw) => text.includes(kw))) return category;
  }
  return 'other';
}

async function main() {
  const snap = await db.collection('listings').get();
  const toUpdate = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.category) continue; // ήδη έχει — δεν το αγγίζουμε
    toUpdate.push({ id: doc.id, guess: guessCategory(d), title: d.title });
  }

  console.log(`Σύνολο αγγελιών: ${snap.size}`);
  console.log(`Χωρίς category: ${toUpdate.length}`);
  const counts = {};
  for (const { guess } of toUpdate) counts[guess] = (counts[guess] || 0) + 1;
  console.log('Κατανομή μαντεψιάς:', counts);
  console.log('---');
  for (const { id, guess, title } of toUpdate.slice(0, 30)) {
    console.log(`${id}  →  ${guess}  ("${title}")`);
  }
  if (toUpdate.length > 30) console.log(`... και ${toUpdate.length - 30} ακόμα`);

  if (!WRITE) {
    console.log('\nDRY RUN — καμία εγγραφή δεν άλλαξε. Τρέξε με --write για να γράψει.');
    return;
  }

  console.log('\nΓράφω...');
  const BATCH_SIZE = 400; // Firestore batch limit 500, ασφαλές περιθώριο
  for (let i = 0; i < toUpdate.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const { id, guess } of toUpdate.slice(i, i + BATCH_SIZE)) {
      batch.update(db.collection('listings').doc(id), { category: guess });
    }
    await batch.commit();
    console.log(`  ${Math.min(i + BATCH_SIZE, toUpdate.length)}/${toUpdate.length}`);
  }
  console.log('Έτοιμο.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
