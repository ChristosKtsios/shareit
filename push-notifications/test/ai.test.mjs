// Unit tests για τις «καθαρές» συναρτήσεις του src/ai.ts — χωρίς δίκτυο,
// χωρίς Gemini API, χωρίς Firebase.  Τρέχει:  npm test
import { test } from "node:test";
import assert from "node:assert/strict";
import ai from "../lib/ai.js";

const {
  sanitizeFilters,
  sanitizeSuggestion,
  parseJsonResponse,
  isOwnListingImagePath,
  detectImageType,
  listingSystemPrompt,
  listingEmbeddingText,
  queryEmbeddingText,
  embeddingHash,
  embeddingAction,
  MIN_SIMILARITY,
} = ai;

const emptyFilters = {
  keywords: [], type: null, category: null, maxDistanceKm: null,
  availableFrom: null, availableUntil: null, sort: null,
};

// ── sanitizeFilters ──────────────────────────────────────────────────────

test("sanitizeFilters: κρατά έγκυρα φίλτρα όπως είναι", () => {
  const f = {
    keywords: ["ποδήλατο", "παιδικό"], type: "offer", category: "kids",
    maxDistanceKm: 5, availableFrom: "2026-10-10",
    availableUntil: "2026-10-11", sort: "nearest",
  };
  assert.deepEqual(sanitizeFilters(f), f);
});

test("sanitizeFilters: απόσταση εκτός ορίων → clamp 1..800, ≤0 → null", () => {
  assert.equal(sanitizeFilters({ ...emptyFilters, maxDistanceKm: 5000 })
    .maxDistanceKm, 800);
  assert.equal(sanitizeFilters({ ...emptyFilters, maxDistanceKm: 0.2 })
    .maxDistanceKm, 1);
  assert.equal(sanitizeFilters({ ...emptyFilters, maxDistanceKm: -3 })
    .maxDistanceKm, null);
});

test("sanitizeFilters: ανάποδες ημερομηνίες αντιστρέφονται", () => {
  const f = sanitizeFilters({
    ...emptyFilters, availableFrom: "2026-10-12", availableUntil: "2026-10-10",
  });
  assert.equal(f.availableFrom, "2026-10-10");
  assert.equal(f.availableUntil, "2026-10-12");
});

test("sanitizeFilters: άκυρες τιμές → null, κενά keywords πετιούνται", () => {
  const f = sanitizeFilters({
    keywords: [" σκηνή ", "", "  "], type: "rent", category: "cars",
    maxDistanceKm: null, availableFrom: "Σάββατο", availableUntil: null,
    sort: "cheapest",
  });
  assert.deepEqual(f, { ...emptyFilters, keywords: ["σκηνή"] });
});

test("sanitizeFilters: το πολύ 8 keywords", () => {
  const f = sanitizeFilters({
    ...emptyFilters, keywords: Array.from({ length: 20 }, (_, i) => `k${i}`),
  });
  assert.equal(f.keywords.length, 8);
});

// ── parseJsonResponse (μορφή απάντησης Gemini) ──────────────────────────

const ok = (parts, finishReason = "STOP") => ({
  candidates: [{ finishReason, content: { parts } }],
});

test("parseJsonResponse: ενώνει τα text parts, αγνοεί τα thought parts", () => {
  const out = parseJsonResponse(ok([
    { text: "σκέφτομαι...", thought: true },
    { text: '{"a":' },
    { text: "1}" },
  ]), "t");
  assert.deepEqual(out, { a: 1 });
});

for (const reason of ["SAFETY", "MAX_TOKENS", "RECITATION", null]) {
  test(`parseJsonResponse: finishReason=${reason} → unavailable`, () => {
    assert.throws(
      () => parseJsonResponse(ok([{ text: "{}" }], reason), "t"),
      (e) => e.code === "unavailable");
  });
}

test("parseJsonResponse: μπλοκαρισμένη είσοδος → unavailable", () => {
  assert.throws(
    () => parseJsonResponse({
      ...ok([{ text: "{}" }]), promptFeedback: { blockReason: "SAFETY" },
    }, "t"),
    (e) => e.code === "unavailable");
});

test("parseJsonResponse: καμία απάντηση → unavailable", () => {
  assert.throws(() => parseJsonResponse({}, "t"),
    (e) => e.code === "unavailable");
});

test("parseJsonResponse: άκυρο JSON → unavailable (όχι crash)", () => {
  assert.throws(() => parseJsonResponse(ok([{ text: "{oops" }]), "t"),
    (e) => e.code === "unavailable");
});

// ── sanitizeSuggestion ───────────────────────────────────────────────────

test("sanitizeSuggestion: κόβει στα όρια της φόρμας", () => {
  const s = sanitizeSuggestion({
    suitable: true,
    title: "x".repeat(200),
    description: "y".repeat(900),
    category: "tools",
    tags: [],
  });
  assert.equal(s.title.length, 80);
  assert.equal(s.description.length, 500);
});

test("sanitizeSuggestion: tags πεζά, χωρίς #, χωρίς διπλά, ≤5, ≤20 χαρ.", () => {
  const s = sanitizeSuggestion({
    suitable: true, title: "Δράπανο", description: "", category: "tools",
    tags: ["#Δράπανο", "δράπανο", "BOSCH", "εργαλεία", "diy", "τρυπάνι",
      "μπαταρίας", "x".repeat(30)],
  });
  assert.deepEqual(s.tags, ["δράπανο", "bosch", "εργαλεία", "diy", "τρυπάνι"]);
});

test("sanitizeSuggestion: suitable=false → αδειάζει τα πάντα", () => {
  const s = sanitizeSuggestion({
    suitable: false, title: "κάτι", description: "κάτι", category: "other",
    tags: ["a"],
  });
  assert.deepEqual(s, {
    suitable: false, title: "", description: "", category: null, tags: [],
  });
});

test("sanitizeSuggestion: άγνωστη κατηγορία → null", () => {
  assert.equal(sanitizeSuggestion({
    suitable: true, title: "a", description: "", category: "pets", tags: [],
  }).category, null);
});

// ── ασφάλεια διαδρομής Storage ───────────────────────────────────────────

test("isOwnListingImagePath: μόνο listings/{ίδιο uid}/", () => {
  assert.equal(isOwnListingImagePath("listings/u1/123_a.jpg", "u1"), true);
  assert.equal(isOwnListingImagePath("listings/u2/123_a.jpg", "u1"), false);
  assert.equal(isOwnListingImagePath("listings/u1", "u1"), false);
  assert.equal(isOwnListingImagePath("chats/c1/a.jpg", "u1"), false);
  // uid-πρόθεμα άλλου χρήστη: «u1» δεν πρέπει να ανοίγει το «u10».
  assert.equal(isOwnListingImagePath("listings/u10/a.jpg", "u1"), false);
});

test("isOwnListingImagePath: απορρίπτει path traversal", () => {
  assert.equal(
    isOwnListingImagePath("listings/u1/../u2/secret.jpg", "u1"), false);
});

// ── detectImageType ──────────────────────────────────────────────────────

test("detectImageType: αναγνωρίζει από magic bytes, όχι κατάληξη", () => {
  assert.equal(detectImageType(Buffer.from([0xff, 0xd8, 0xff, 0xe0])),
    "image/jpeg");
  assert.equal(detectImageType(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d])),
    "image/png");
  assert.equal(detectImageType(Buffer.from("RIFF\0\0\0\0WEBPVP8 ")),
    "image/webp");
  assert.equal(detectImageType(Buffer.from("%PDF-1.7")), null);
  assert.equal(detectImageType(Buffer.from([])), null);
});

// ── prompt ───────────────────────────────────────────────────────────────

test("listingSystemPrompt: γλώσσα και πρόθεση περνούν στο prompt", () => {
  const offer = listingSystemPrompt("Greek", "offer");
  assert.match(offer, /Write in Greek, in its native script/);
  assert.match(offer, /never Latin letters/);
  assert.match(offer, /OFFERING/);
  assert.match(listingSystemPrompt("Hindi", "seek"), /LOOKING FOR/);
  // Το backslash-newline του template literal δεν αφήνει σπασμένες λέξεις.
  assert.doesNotMatch(offer, /\\\n/);
});

// ── semantic search: embeddings ──────────────────────────────────────────

const drill = {
  title: "Δραπανοκατσάβιδο", description: "Με δύο μπαταρίες.",
  category: "tools", tags: ["δράπανο", "diy"], isActive: true,
};

test("listingEmbeddingText: μορφή title/text του gemini-embedding-2", () => {
  assert.equal(listingEmbeddingText(drill),
    "title: Δραπανοκατσάβιδο | text: tools. δράπανο diy. Με δύο μπαταρίες.");
});

test("listingEmbeddingText: ανέχεται κενά/λάθος τύπους πεδίων", () => {
  assert.equal(listingEmbeddingText({}), "title: none | text: ");
  assert.equal(
    listingEmbeddingText({ title: "Σκάλα", tags: ["a", 3, null], category: 7 }),
    "title: Σκάλα | text: a");
});

test("queryEmbeddingText: πρόθεμα ερωτήματος", () => {
  assert.equal(queryEmbeddingText("  μεταφορά καναπέ "),
    "task: search result | query: μεταφορά καναπέ");
});

test("embeddingHash: ίδιο κείμενο → ίδιο hash, άλλο κείμενο → άλλο", () => {
  const t = listingEmbeddingText(drill);
  assert.equal(embeddingHash(t), embeddingHash(t));
  assert.notEqual(embeddingHash(t), embeddingHash(t + "!"));
  assert.equal(embeddingHash(t).length, 16);
});

const stored = (l, isActive = true) =>
  ({ hash: embeddingHash(listingEmbeddingText(l)), isActive });

test("embeddingAction: σβησμένη αγγελία → delete", () => {
  assert.equal(embeddingAction(undefined, stored(drill)), "delete");
});

test("embeddingAction: χωρίς embedding → embed", () => {
  assert.equal(embeddingAction(drill, undefined), "embed");
});

test("embeddingAction: αλλαγή τίτλου/περιγραφής/tags → embed", () => {
  assert.equal(embeddingAction({ ...drill, title: "Τρυπάνι" }, stored(drill)),
    "embed");
  assert.equal(embeddingAction({ ...drill, tags: ["x"] }, stored(drill)),
    "embed");
});

test("embeddingAction: boost/σχόλιο (ίδιο κείμενο) → skip", () => {
  const boosted = { ...drill, boostTimestamps: [1], commentsCount: 4 };
  assert.equal(embeddingAction(boosted, stored(drill)), "skip");
});

test("embeddingAction: μόνο το isActive άλλαξε → syncActive", () => {
  assert.equal(embeddingAction({ ...drill, isActive: false }, stored(drill)),
    "syncActive");
  assert.equal(embeddingAction(drill, stored(drill, false)), "syncActive");
});

test("embeddingAction: λείπει το isActive → θεωρείται ενεργή", () => {
  const { isActive: _ignored, ...legacy } = drill;
  assert.equal(embeddingAction(legacy, stored(drill, true)), "skip");
});

test("MIN_SIMILARITY: στο βαθμονομημένο εύρος", () => {
  assert.ok(MIN_SIMILARITY > 0.6 && MIN_SIMILARITY < 0.75);
});
