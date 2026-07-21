/**
 * seed-demo.mjs — φυτεύει ΚΑΘΑΡΕΣ demo αγγελίες για store screenshots.
 *
 *   node seed-demo.mjs          → δημιουργεί 8 demo αγγελίες στην Αθήνα
 *   node seed-demo.mjs --clean  → σβήνει ΟΛΕΣ τις demo (flag _demoSeed)
 *
 * Χρειάζεται: export GOOGLE_APPLICATION_CREDENTIALS=/path/serviceAccount.json
 * Όλα τα docs έχουν `_demoSeed: true` → καθαρίζονται εύκολα, δεν αγγίζουν
 * πραγματικές αγγελίες.
 */
import admin from 'firebase-admin';

admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();
const { GeoPoint, FieldValue } = admin.firestore;

const CLEAN = process.argv.includes('--clean');
const DEMO_UID = 'demo-seed-user';

// Αθήνα κέντρο, με μικρές μετατοπίσεις ώστε να απλώνονται στον χάρτη.
const L = [
  { t: 'offer', name: 'Γιώργος', title: 'Τρυπάνι Bosch',        desc: 'Δανείζω κρουστικό τρυπάνι για ένα σαββατοκύριακο. Μαζί σετ τρυπάνια.', label: 'Σύνταγμα, Αθήνα',      lat: 37.9838, lng: 23.7275, tags: ['εργαλεια','diy'] },
  { t: 'offer', name: 'Μαρία',   title: 'Ποδήλατο πόλης',        desc: 'Αστικό ποδήλατο 28άρι σε άριστη κατάσταση, με καλάθι και φως.',        label: 'Παγκράτι, Αθήνα',      lat: 37.9755, lng: 23.7348, tags: ['ποδηλατο','μεταφορα'] },
  { t: 'offer', name: 'Νίκος',   title: 'Μαθήματα κιθάρας',      desc: 'Παραδίδω μαθήματα κιθάρας για αρχάριους. Πρώτο μάθημα δωρεάν.',        label: 'Εξάρχεια, Αθήνα',      lat: 37.9922, lng: 23.7330, tags: ['μουσικη','μαθηματα'] },
  { t: 'seek',  name: 'Ελένη',   title: 'Ζητώ σκάλα αλουμινίου', desc: 'Χρειάζομαι σκάλα 3 μέτρων για μια μέρα, για βάψιμο.',                 label: 'Κουκάκι, Αθήνα',       lat: 37.9715, lng: 23.7267, tags: ['εργαλεια'] },
  { t: 'offer', name: 'Δημήτρης',title: 'Καναπές διθέσιος',      desc: 'Χαρίζω διθέσιο καναπέ σε καλή κατάσταση. Παραλαβή από το σπίτι.',      label: 'Θησείο, Αθήνα',        lat: 37.9880, lng: 23.7180, tags: ['επιπλα','σπιτι'] },
  { t: 'offer', name: 'Άννα',    title: 'Βαλίτσα ταξιδιού',      desc: 'Δανείζω μεγάλη βαλίτσα trolley για τις διακοπές σας.',                label: 'Μετς, Αθήνα',          lat: 37.9790, lng: 23.7420, tags: ['ταξιδι'] },
  { t: 'seek',  name: 'Κώστας',  title: 'Ζητώ φύλαξη σκύλου',    desc: 'Ψάχνω κάποιον να κρατήσει τον σκύλο μου για ένα σαββατοκύριακο.',     label: 'Μεταξουργείο, Αθήνα',  lat: 37.9950, lng: 23.7200, tags: ['κατοικιδια','υπηρεσιες'] },
  { t: 'offer', name: 'Σοφία',   title: 'Ψησταριά κήπου',        desc: 'Δανείζω ψησταριά κάρβουνου για μπάρμπεκιου. Ιδανική για παρέες.',     label: 'Νέος Κόσμος, Αθήνα',   lat: 37.9680, lng: 23.7350, tags: ['κηπος','εκδηλωσεις'] },
];

// Ίδια λογική με ListingModel.tokenize (Dart): fold τόνων + λέξεις >2 χαρ.
const FOLD = {
  'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω',
  'ϊ': 'ι', 'ϋ': 'υ', 'ΐ': 'ι', 'ΰ': 'υ', 'ς': 'σ',
};
const fold = (s) => s.toLowerCase().split('').map((c) => FOLD[c] ?? c).join('');
const words = (t, doFold) => (doFold ? fold(t) : t.toLowerCase())
  .replace(/[^\w\sα-ωάέήίόύώϊϋΐΰ]/gu, ' ')
  .split(/\s+/).filter((w) => w.length > 2);
// Άτονα (νέα αναζήτηση) + τονισμένα (παλιά έκδοση app) — όπως generateKeywords.
const keywords = (a, b) => [...new Set(
  [...words(`${a} ${b}`, true), ...words(`${a} ${b}`, false)]
)];

async function clean() {
  const snap = await db.collection('listings').where('_demoSeed', '==', true).get();
  if (snap.empty) { console.log('✅ Καμία demo αγγελία για διαγραφή.'); return; }
  console.log(`🗑  Διαγραφή ${snap.size} demo αγγελιών...`);
  for (const d of snap.docs) { await d.ref.delete(); console.log(`   ✓ ${d.id}`); }
  console.log('✅ Καθαρίστηκαν.');
}

async function seed() {
  console.log(`🌱 Δημιουργία ${L.length} demo αγγελιών...`);
  for (const x of L) {
    await db.collection('listings').add({
      _demoSeed: true,
      userId: DEMO_UID,
      userFirstName: x.name,
      userAvatarUrl: null,
      type: x.t,
      title: x.title,
      description: x.desc,
      locationLabel: x.label,
      imageUrls: [],
      tags: x.tags,
      searchKeywords: keywords(x.title, x.desc),
      location: new GeoPoint(x.lat, x.lng),
      availableFrom: null, availableUntil: null,
      hasFromTime: false, hasUntilTime: false,
      autoDelete: false, rating: 0,
      isActive: true, isReported: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    console.log(`   ✓ ${x.title}`);
  }
  console.log('✅ Έτοιμο. Άνοιξε την app για screenshots. Καθάρισμα: node seed-demo.mjs --clean');
}

(CLEAN ? clean() : seed()).then(() => process.exit(0));
