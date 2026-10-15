/**
 * AI functions (Gemini API, δωρεάν πρόγραμμα).
 *
 * ΑΣΦΑΛΕΙΑ: το GEMINI_API_KEY ζει ΜΟΝΟ εδώ, στο Secret Manager — ποτέ στην
 * εφαρμογή. Ένα key μέσα στο APK εξάγεται σε λεπτά και καταναλώνει το όριό σου.
 *   Key:      https://aistudio.google.com/apikey
 *   Ρύθμιση:  firebase functions:secrets:set GEMINI_API_KEY
 *
 * ΔΕΔΟΜΕΝΑ: στο δωρεάν πρόγραμμα η Google κανονικά χρησιμοποιεί τα δεδομένα
 * για βελτίωση των μοντέλων — ΕΚΤΟΣ από ΕΟΧ/Ελβετία/ΗΒ, όπου ισχύουν οι όροι
 * του πληρωμένου (ai.google.dev/gemini-api/terms). Οι όροι απαγορεύουν επίσης
 * χρήση σε εφαρμογή που απευθύνεται σε ανηλίκους (<18).
 *
 * ΚΟΣΤΟΣ: κάθε κλήση περνά από [consumeAiQuota] (όριο ανά χρήστη ΚΑΙ καθολικό
 * ανά ημέρα), ώστε ένας κακόβουλος χρήστης να μη μπορεί να «φουσκώσει» τον
 * λογαριασμό.
 */
import * as admin from "firebase-admin";
import { createHash } from "node:crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { ApiError, FinishReason, GoogleGenAI } from "@google/genai";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

// Flash-Lite: η μετατροπή μιας φράσης σε φίλτρα είναι απλή εξαγωγή δομής —
// το ελαφρύτερο/γρηγορότερο μοντέλο αρκεί. Αλλάζει από εδώ, σε ένα σημείο.
export const SEARCH_MODEL = "gemini-3.5-flash-lite";

const AI_DAILY_LIMIT_PER_USER = 50;
const AI_DAILY_LIMIT_GLOBAL = 3000;
const MAX_QUERY_LENGTH = 300;

// ΠΡΕΠΕΙ να ταυτίζεται με το enum ListingCategory (listing_model.dart).
const CATEGORIES = [
  "electronics", "furniture", "clothing", "books", "sports",
  "kids", "tools", "transport", "services", "other",
] as const;

/** "Σήμερα" σε ώρα Ελλάδας (YYYY-MM-DD) — εκεί ζουν οι χρήστες. */
function todayAthens(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Athens" })
    .format(new Date());
}

/**
 * Μετρητής ανά ημέρα σε transaction. Πετάει `resource-exhausted` όταν
 * ξεπεραστεί είτε το όριο του χρήστη είτε το καθολικό.
 */
async function consumeAiQuota(uid: string): Promise<void> {
  const db = admin.firestore();
  const day = todayAthens();
  const userRef = db.collection("aiUsage").doc(`${uid}_${day}`);
  const globalRef = db.collection("aiUsage").doc(`GLOBAL_${day}`);

  const exhausted = await db.runTransaction(async (tx) => {
    const [u, g] = await Promise.all([tx.get(userRef), tx.get(globalRef)]);
    const uCount = (u.data()?.count as number) ?? 0;
    const gCount = (g.data()?.count as number) ?? 0;
    if (uCount >= AI_DAILY_LIMIT_PER_USER || gCount >= AI_DAILY_LIMIT_GLOBAL) {
      return true;
    }
    tx.set(userRef, { uid, day, count: uCount + 1 }, { merge: true });
    tx.set(globalRef, { day, count: gCount + 1 }, { merge: true });
    return false;
  });

  if (exhausted) {
    logger.warn(`AI quota exhausted for ${uid}`);
    throw new HttpsError("resource-exhausted", "ai-quota");
  }
}

/** nullable τύπος για το JSON schema των structured outputs. */
const nullable = (schema: Record<string, unknown>) => ({
  anyOf: [schema, { type: "null" }],
});

// Structured output (responseJsonSchema): το μοντέλο περιορίζεται σε αυτό το
// schema — δεν χρειάζεται «παρακαλώ απάντησε σε JSON» ούτε regex parsing.
export const SEARCH_FILTERS_SCHEMA = {
  type: "object",
  properties: {
    keywords: {
      type: "array",
      items: { type: "string" },
      description: "Ουσιαστικά/αντικείμενα για αναζήτηση κειμένου, " +
        "στην ονομαστική ενικού, μαζί με 1-3 συνώνυμα.",
    },
    type: nullable({ type: "string", enum: ["offer", "seek"] }),
    category: nullable({ type: "string", enum: [...CATEGORIES] }),
    maxDistanceKm: nullable({ type: "number" }),
    availableFrom: nullable({ type: "string", format: "date" }),
    availableUntil: nullable({ type: "string", format: "date" }),
    sort: nullable({ type: "string", enum: ["recent", "nearest"] }),
  },
  required: [
    "keywords", "type", "category", "maxDistanceKm",
    "availableFrom", "availableUntil", "sort",
  ],
  additionalProperties: false,
};

export const SEARCH_SYSTEM_PROMPT = `Μετατρέπεις το ερώτημα αναζήτησης ενός χρήστη \
σε φίλτρα για μια εφαρμογή δανεισμού/ανταλλαγής αντικειμένων («Share your \
Need»). Οι αγγελίες είναι «offer» (κάποιος ΠΡΟΣΦΕΡΕΙ κάτι) ή «seek» (κάποιος \
ΖΗΤΑΕΙ κάτι).

Κανόνες:
- type: ο χρήστης που ψάχνει/χρειάζεται κάτι θέλει να βρει αγγελίες «offer». \
Αν λέει ότι θέλει να δώσει/δανείσει κάτι, θέλει αγγελίες «seek». Αλλιώς null.
- keywords: τα αντικείμενα/υπηρεσίες που ψάχνει, στην ονομαστική ενικού, \
χωρίς ρήματα/επίθετα γεμίσματος («ψάχνω», «θέλω», «κοντά»). Πρόσθεσε 1-2 \
κοινά συνώνυμα (π.χ. τρυπάνι → δράπανο). Οι αγγελίες είναι κυρίως στα \
ελληνικά: αν το ερώτημα είναι σε άλλη γλώσσα ή greeklish, δώσε ΚΑΙ τις \
ελληνικές λέξεις. Κενή λίστα αν δεν αναφέρει αντικείμενο.
- category: είναι ΑΥΣΤΗΡΟ φίλτρο που κρύβει ό,τι δεν ταιριάζει. Βάλ' το ΜΟΝΟ \
όταν ο χρήστης ζητά ρητά ολόκληρη κατηγορία χωρίς συγκεκριμένο αντικείμενο \
(π.χ. «εργαλεία», «παιδικά ρούχα», «κάτι για διάβασμα»). Αν αναφέρει \
συγκεκριμένο αντικείμενο (σκάλα, ποδήλατο, τρυπάνι), category = null — τα \
keywords αρκούν. Όταν βάζεις category, ΜΗΝ βάζεις στα keywords το όνομα της \
ίδιας της κατηγορίας («εργαλεία», «βιβλία») — μόνο επιπλέον λεπτομέρειες.
- maxDistanceKm: «κοντά μου» ≈ 5, «στη γειτονιά» ≈ 2, «στην πόλη» ≈ 15, ρητός \
αριθμός όπως δίνεται. Αλλιώς null.
- availableFrom/availableUntil: μόνο αν αναφέρει χρόνο. Υπολόγισε από τη \
σημερινή ημερομηνία που δίνεται. Μία μέρα → ίδια τιμή και στα δύο.
- sort: «nearest» αν δίνει έμφαση στην εγγύτητα, αλλιώς null.
Μην εφευρίσκεις φίλτρα που ο χρήστης δεν ζήτησε.`;

export interface SearchFilters {
  keywords: string[];
  type: "offer" | "seek" | null;
  category: (typeof CATEGORIES)[number] | null;
  maxDistanceKm: number | null;
  availableFrom: string | null;
  availableUntil: string | null;
  sort: "recent" | "nearest" | null;
}

/**
 * Φυσική γλώσσα → φίλτρα αναζήτησης.
 *   in:  { query: "ψάχνω παιδικό ποδήλατο κοντά μου για το Σάββατο" }
 *   out: SearchFilters
 *
 * Ο client δείχνει τα φίλτρα ως chips (ο χρήστης βλέπει τι «κατάλαβε» το AI
 * και το διορθώνει) και τρέχει την ΥΠΑΡΧΟΥΣΑ αναζήτηση — το AI δεν αγγίζει
 * ποτέ τη βάση, μόνο προτείνει φίλτρα.
 */
export const parseSearchQuery = onCall(
  {
    secrets: [GEMINI_API_KEY],
    // Ίδιος λόγος με checkAccountExists (index.ts): App Check απορρίπτει
    // ακόμα τη γνήσια εφαρμογή. Προστασία μέσω auth + quota προς το παρόν.
    enforceAppCheck: false,
    timeoutSeconds: 30,
    maxInstances: 5,
  },
  async (request): Promise<SearchFilters & { matches: SemanticMatch[] }> => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Login required");

    const query = String(request.data?.query ?? "").trim();
    if (!query) throw new HttpsError("invalid-argument", "Empty query");
    if (query.length > MAX_QUERY_LENGTH) {
      throw new HttpsError("invalid-argument", "Query too long");
    }

    await consumeAiQuota(uid);

    const today = todayAthens();
    const weekday = new Intl.DateTimeFormat("el-GR", {
      timeZone: "Europe/Athens", weekday: "long",
    }).format(new Date());

    // ΠΑΡΑΛΛΗΛΑ: φίλτρα (LLM) + σημασιολογικά αποτελέσματα (embeddings).
    // Μία κλήση από τον client, μία μονάδα quota. Το semantic είναι
    // «μπόνους»: αν αποτύχει, τα φίλτρα επιστρέφονται κανονικά.
    const [response, matches] = await Promise.all([
      generateJson({
        model: SEARCH_MODEL,
        system: SEARCH_SYSTEM_PROMPT,
        schema: SEARCH_FILTERS_SCHEMA,
        parts: [{ text: `Σήμερα: ${today} (${weekday})\nΕρώτημα: ${query}` }],
      }),
      semanticMatches(query).catch((e) => {
        logger.warn("semanticMatches failed", e);
        return [] as SemanticMatch[];
      }),
    ]);

    return {
      ...sanitizeFilters(
        parseJsonResponse<SearchFilters>(response, "parseSearchQuery")),
      matches,
    };
  }
);

type Part = { text: string } |
  { inlineData: { mimeType: string; data: string } };

/** Η μορφή απάντησης που χρειαζόμαστε από το Gemini (για tests: plain obj). */
export interface JsonCandidateResponse {
  candidates?: ReadonlyArray<{
    finishReason?: string;
    content?: { parts?: ReadonlyArray<{ text?: string; thought?: boolean }> };
  }>;
  promptFeedback?: { blockReason?: string };
}

/**
 * Μία κλήση στο Gemini με structured output. Κάθε σφάλμα → HttpsError, ώστε
 * ο client να έχει ΕΝΑΝ τύπο σφάλματος (και να συνεχίζει χωρίς AI).
 */
async function generateJson(args: {
  model: string;
  system: string;
  schema: Record<string, unknown>;
  parts: Part[];
}): Promise<JsonCandidateResponse> {
  const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
  try {
    return await ai.models.generateContent({
      model: args.model,
      contents: [{ role: "user", parts: args.parts }],
      config: {
        systemInstruction: args.system,
        responseMimeType: "application/json",
        responseJsonSchema: args.schema,
        maxOutputTokens: 2048,
      },
    });
  } catch (e) {
    throw toHttpsError(e);
  }
}

/**
 * Παίρνει το JSON από την απάντηση του Gemini.
 *
 * ΜΟΝΟ τα text parts της πρώτης απάντησης — όχι τα «thought» parts (σκέψεις
 * του μοντέλου). Κάθε finishReason εκτός από STOP σημαίνει ότι το JSON
 * μπορεί να είναι μισό (MAX_TOKENS) ή μπλοκαρισμένο (SAFETY) — δεν το
 * εμπιστευόμαστε. Ίδια λογική αν μπλοκαρίστηκε ήδη η είσοδος (promptFeedback).
 */
export function parseJsonResponse<T>(
  response: JsonCandidateResponse,
  label: string
): T {
  const candidate = response.candidates?.[0];
  if (response.promptFeedback?.blockReason ||
      candidate?.finishReason !== FinishReason.STOP) {
    logger.warn(`${label} finish=${candidate?.finishReason} ` +
      `block=${response.promptFeedback?.blockReason}`);
    throw new HttpsError("unavailable", "ai-unavailable");
  }
  const text = (candidate.content?.parts ?? [])
    .filter((p) => !p.thought)
    .map((p) => p.text ?? "")
    .join("");
  try {
    return JSON.parse(text) as T;
  } catch {
    logger.error(`${label}: invalid JSON`, text.slice(0, 200));
    throw new HttpsError("unavailable", "ai-unavailable");
  }
}

/** Κοινός χειρισμός σφαλμάτων του Gemini API για όλα τα AI callables. */
function toHttpsError(e: unknown): HttpsError {
  if (e instanceof HttpsError) return e;
  if (e instanceof ApiError) {
    logger.error(`Gemini API ${e.status}: ${e.message}`);
    // 429 = το δωρεάν όριο της Google ΑΝΑ ΛΕΠΤΟ (~15-20 κλήσεις, μετρημένο
    // 7/10/2026). ΟΧΙ resource-exhausted: αυτό ο client το δείχνει ως
    // «ημερήσιο όριο» (δικό μας, consumeAiQuota) — εδώ αρκεί «δοκίμασε ξανά».
    if (e.status === 429) {
      return new HttpsError("unavailable", "ai-busy");
    }
  } else {
    logger.error("Gemini call failed", e);
  }
  // Ο client σε αυτή την περίπτωση συνεχίζει χωρίς AI.
  return new HttpsError("unavailable", "ai-unavailable");
}

/**
 * Τελευταία γραμμή άμυνας: το schema εγγυάται τη ΜΟΡΦΗ, όχι λογικές τιμές
 * (π.χ. αρνητική απόσταση ή ανάποδες ημερομηνίες).
 */
export function sanitizeFilters(f: SearchFilters): SearchFilters {
  const isDate = (s: string | null) =>
    s !== null && /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : null;
  let from = isDate(f.availableFrom);
  let until = isDate(f.availableUntil);
  if (from && until && from > until) [from, until] = [until, from];

  const km = f.maxDistanceKm;
  return {
    keywords: (f.keywords ?? [])
      .map((k) => k.trim())
      .filter((k) => k.length > 0)
      .slice(0, 8),
    type: f.type === "offer" || f.type === "seek" ? f.type : null,
    category: CATEGORIES.includes(f.category as never) ? f.category : null,
    maxDistanceKm: typeof km === "number" && km > 0 ?
      Math.min(Math.max(km, 1), 800) : null,
    availableFrom: from,
    availableUntil: until,
    sort: f.sort === "nearest" || f.sort === "recent" ? f.sort : null,
  };
}

// ══════════════════════════════════════════════════════════════════════════
// Αγγελία από φωτογραφία
// ══════════════════════════════════════════════════════════════════════════

// Flash-Lite και εδώ. Μετρημένο 7/10/2026 στο ΔΩΡΕΑΝ πρόγραμμα: το
// gemini-3.8-flash έδινε ελαφρώς καλύτερο κείμενο αλλά 86s ή «503 high
// demand» (οι δωρεάν χρήστες έχουν τη χαμηλότερη προτεραιότητα)· το Lite
// 1-3s, σωστή αναγνώριση και απόρριψη εγγράφων ταυτότητας.
export const VISION_MODEL = "gemini-3.5-flash-lite";
// Η φόρμα στέλνει ≤1600px JPEG (~0.5MB). Το όριο κόβει μόνο κακόβουλα αρχεία.
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const MAX_TAGS = 5; // ίδιο με create_listing_screen.dart (_maxTags)

const LANGUAGES: Record<string, string> = {
  el: "Greek", en: "English", es: "Spanish", hi: "Hindi",
};

export const LISTING_SUGGESTION_SCHEMA = {
  type: "object",
  properties: {
    suitable: {
      type: "boolean",
      description: "false αν η εικόνα δεν δείχνει αντικείμενο/υπηρεσία " +
        "κατάλληλη για αγγελία.",
    },
    title: { type: "string" },
    description: { type: "string" },
    category: nullable({ type: "string", enum: [...CATEGORIES] }),
    tags: { type: "array", items: { type: "string" } },
  },
  required: ["suitable", "title", "description", "category", "tags"],
  additionalProperties: false,
};

/** System prompt ανά γλώσσα/τύπο — σταθερό κείμενο, χωρίς δεδομένα χρήστη. */
export function listingSystemPrompt(
  language: string, type: "offer" | "seek"
): string {
  const intent = type === "offer" ?
    "The user is OFFERING this item (lending, giving away or swapping it)." :
    "The user is LOOKING FOR an item like this one (wants to borrow it).";
  return `You write listings for "Share your Need", a neighbourhood app for \
lending, borrowing and swapping things. You get one photo taken by the user. \
${intent}

Write in ${language}, in its native script with correct accents and \
spelling (for Greek: Greek alphabet with tonos, never Latin letters or \
"greeklish"). Tags too.
- title: what the item is, at most 60 characters, no emoji, no price.
- description: 2-3 short sentences for neighbours: what it is, visible \
condition, what it is useful for. Only state what is visible in the photo - \
mention a brand or model only if it is clearly readable. At most 400 \
characters. No contact details.
- category: the closest category, or null if none fits.
- tags: 3-5 single lowercase words someone would search for, without "#".
- suitable: false if the photo has no identifiable item or service (blank, \
blurry, screenshot of text), shows an identity document or bank card, or \
shows people, animals for sale, weapons, drugs or adult content. When false, \
leave title/description empty and tags empty.`;
}

export interface ListingSuggestion {
  suitable: boolean;
  title: string;
  description: string;
  category: (typeof CATEGORIES)[number] | null;
  tags: string[];
}

/** Όρια ίδια με τη φόρμα (title 80, description 500, tags ≤5 × ≤20 χαρ.). */
export function sanitizeSuggestion(s: ListingSuggestion): ListingSuggestion {
  if (!s.suitable) {
    return {
      suitable: false, title: "", description: "", category: null, tags: [],
    };
  }
  const tags = Array.from(new Set((s.tags ?? [])
    .map((t) => String(t).toLowerCase().replace(/^#+/, "").trim()
      .replace(/\s+/g, " "))
    .filter((t) => t.length > 0 && t.length <= 20)))
    .slice(0, MAX_TAGS);
  return {
    suitable: true,
    title: String(s.title ?? "").trim().slice(0, 80),
    description: String(s.description ?? "").trim().slice(0, 500),
    category: CATEGORIES.includes(s.category as never) ? s.category : null,
    tags,
  };
}

/**
 * Μόνο εικόνες αγγελιών ΤΟΥ ΙΔΙΟΥ του χρήστη (`listings/{uid}/...`) — αλλιώς
 * θα μπορούσε κάποιος να «διαβάσει» μέσω AI οποιοδήποτε αρχείο του bucket.
 * Απορρίπτει και `..` (path traversal).
 */
export function isOwnListingImagePath(path: string, uid: string): boolean {
  return path.startsWith(`listings/${uid}/`) && !path.includes("..");
}

/** Τύπος εικόνας από τα πρώτα bytes (magic numbers) — όχι από την κατάληξη. */
export function detectImageType(
  buf: Uint8Array
): "image/jpeg" | "image/png" | "image/webp" | null {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
    return "image/jpeg";
  }
  if (buf.length >= 4 && buf[0] === 0x89 && buf[1] === 0x50 &&
      buf[2] === 0x4e && buf[3] === 0x47) {
    return "image/png";
  }
  if (buf.length >= 12 &&
      String.fromCharCode(...buf.slice(0, 4)) === "RIFF" &&
      String.fromCharCode(...buf.slice(8, 12)) === "WEBP") {
    return "image/webp";
  }
  return null;
}

/**
 * Φωτογραφία → προτεινόμενος τίτλος, περιγραφή, κατηγορία, tags.
 *   in:  { storagePath: "listings/{uid}/....jpg", type: "offer"|"seek",
 *          locale: "el" }
 *   out: ListingSuggestion
 *
 * Η εικόνα έχει ΗΔΗ ανέβει στο Storage (μπαίνει στην αγγελία έτσι κι αλλιώς)
 * — στέλνουμε μόνο τη διαδρομή, όχι MB base64 μέσα από το callable.
 */
export const suggestListingFromImage = onCall(
  {
    secrets: [GEMINI_API_KEY],
    enforceAppCheck: false, // βλ. parseSearchQuery
    timeoutSeconds: 60,
    memory: "512MiB",
    maxInstances: 5,
  },
  async (request): Promise<ListingSuggestion> => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Login required");

    const path = String(request.data?.storagePath ?? "");
    if (!isOwnListingImagePath(path, uid)) {
      throw new HttpsError("permission-denied", "Not your image");
    }
    const type = request.data?.type === "seek" ? "seek" : "offer";
    const language = LANGUAGES[String(request.data?.locale ?? "el")] ??
      LANGUAGES.el;

    const file = admin.storage().bucket().file(path);
    const [meta] = await file.getMetadata().catch(() => {
      throw new HttpsError("not-found", "Image not found");
    });
    if (Number(meta.size ?? 0) > MAX_IMAGE_BYTES) {
      throw new HttpsError("invalid-argument", "Image too large");
    }
    const [bytes] = await file.download();
    const mediaType = detectImageType(bytes);
    if (!mediaType) throw new HttpsError("invalid-argument", "Not an image");

    await consumeAiQuota(uid);

    const response = await generateJson({
      model: VISION_MODEL,
      system: listingSystemPrompt(language, type),
      schema: LISTING_SUGGESTION_SCHEMA,
      parts: [
        { inlineData: { mimeType: mediaType, data: bytes.toString("base64") } },
        { text: "Write the listing for this photo." },
      ],
    });

    return sanitizeSuggestion(parseJsonResponse<ListingSuggestion>(
      response, "suggestListingFromImage"));
  }
);

// ══════════════════════════════════════════════════════════════════════════
// Semantic search (embeddings + Firestore vector search)
// ══════════════════════════════════════════════════════════════════════════
//
// Κάθε αγγελία → διάνυσμα 768 αριθμών που κωδικοποιεί το ΝΟΗΜΑ της. Κοντινά
// διανύσματα = παρόμοιο νόημα, άρα το «μεταφορά καναπέ» βρίσκει το «Βοήθεια
// σε μετακόμιση» χωρίς καμία κοινή λέξη.
//
// Τα διανύσματα ζουν σε ΞΕΧΩΡΙΣΤΗ συλλογή `listingEmbeddings/{listingId}`, όχι
// μέσα στην αγγελία: ~6KB/αγγελία που αλλιώς θα κατέβαζε κάθε κινητό σε κάθε
// ανάγνωση του feed. Η συλλογή είναι κλειστή στους clients (κανένα rule →
// deny)· τη διαβάζει/γράφει μόνο ο server.

export const EMBED_MODEL = "gemini-embedding-2";
export const EMBED_DIM = 768; // Firestore: έως 2048 διαστάσεις ανά vector

/**
 * Ελάχιστη ομοιότητα (cosine) για να θεωρηθεί μια αγγελία σχετική.
 *
 * Βαθμονομημένο 7/10/2026 με πραγματικά embeddings (ελληνικές αγγελίες και
 * ερωτήματα): οι σωστές αντιστοιχίσεις έπαιρναν 0.66-0.76, οι άσχετες
 * 0.55-0.66 (π.χ. «ηλεκτρική κιθάρα» → φριτέζα 0.656). Με 0.66: 6/8 σωστά
 * και ΚΑΝΕΝΑ άσχετο. Προτιμάμε ακρίβεια — η αναζήτηση λέξεων καλύπτει τα
 * υπόλοιπα. Αν αλλάξει μοντέλο/διάσταση/μορφή κειμένου, ξαναβαθμονόμησε.
 */
export const MIN_SIMILARITY = 0.66;
const MAX_SEMANTIC_RESULTS = 20;

export interface SemanticMatch {
  id: string;
  /** cosine similarity, 0..1 */
  score: number;
}

interface ListingLike {
  title?: unknown;
  description?: unknown;
  category?: unknown;
  tags?: unknown;
}

/**
 * Το κείμενο που «διαβάζει» το μοντέλο για μια αγγελία. Το gemini-embedding-2
 * δεν έχει taskType· η χρήση δηλώνεται με πρόθεμα (βλ. ai.google.dev/
 * gemini-api/docs/embeddings): «title: … | text: …» για έγγραφα.
 */
export function listingEmbeddingText(d: ListingLike): string {
  const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
  const tags = Array.isArray(d.tags) ?
    d.tags.filter((t): t is string => typeof t === "string").join(" ") : "";
  const text = [str(d.category), tags, str(d.description)]
    .filter((x) => x.length > 0)
    .join(". ");
  return `title: ${str(d.title) || "none"} | text: ${text}`;
}

/** Πρόθεμα για ερωτήματα — το αντίστοιχο του «title/text» των εγγράφων. */
export function queryEmbeddingText(query: string): string {
  return `task: search result | query: ${query.trim()}`;
}

/**
 * Αποτύπωμα του κειμένου + ρυθμίσεων. Αν δεν άλλαξε, ΔΕΝ ξαναϋπολογίζουμε
 * (π.χ. ένα boost ή ένα νέο σχόλιο αλλάζει την αγγελία αλλά όχι το νόημά της).
 * Περιέχει μοντέλο/διάσταση ώστε μια αλλαγή τους να ξαναφτιάξει τα πάντα.
 */
export function embeddingHash(text: string): string {
  return createHash("sha256")
    .update(`${EMBED_MODEL}|${EMBED_DIM}|${text}`)
    .digest("hex")
    .slice(0, 16);
}

async function embedTexts(texts: string[]): Promise<number[][]> {
  const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
  const res = await ai.models.embedContent({
    model: EMBED_MODEL,
    contents: texts.map((text) => ({ parts: [{ text }] })),
    config: { outputDimensionality: EMBED_DIM },
  });
  const vectors = (res.embeddings ?? []).map((e) => e.values ?? []);
  if (vectors.length !== texts.length ||
      vectors.some((v) => v.length !== EMBED_DIM)) {
    throw new Error(`embedContent: unexpected shape (${vectors.length})`);
  }
  return vectors;
}

/** Οι πιο κοντινές ενεργές αγγελίες στο νόημα του ερωτήματος. */
async function semanticMatches(query: string): Promise<SemanticMatch[]> {
  const [vector] = await embedTexts([queryEmbeddingText(query)]);
  const snap = await admin.firestore().collection("listingEmbeddings")
    .where("isActive", "==", true)
    .findNearest({
      vectorField: "embedding",
      queryVector: vector,
      limit: MAX_SEMANTIC_RESULTS,
      distanceMeasure: "COSINE",
      distanceResultField: "_distance",
      // COSINE distance = 1 - similarity.
      distanceThreshold: 1 - MIN_SIMILARITY,
    })
    .get();
  return snap.docs.map((d) => ({
    id: d.id,
    score: Math.round((1 - (d.get("_distance") as number)) * 1000) / 1000,
  }));
}

/**
 * Τι πρέπει να γίνει με το embedding μιας αγγελίας;
 *   "delete"     → η αγγελία σβήστηκε
 *   "embed"      → νέο/αλλαγμένο κείμενο: ξαναϋπολογισμός
 *   "syncActive" → μόνο το isActive άλλαξε (π.χ. απενεργοποίηση): φτηνή ενημέρωση
 *   "skip"       → τίποτα (π.χ. boost, σχόλιο)
 */
export function embeddingAction(
  listing: (ListingLike & { isActive?: unknown }) | undefined,
  existing: { hash?: unknown; isActive?: unknown } | undefined
): "delete" | "embed" | "syncActive" | "skip" {
  if (!listing) return "delete";
  const active = listing.isActive !== false;
  if (!existing || existing.hash !== embeddingHash(listingEmbeddingText(listing))) {
    return "embed";
  }
  return existing.isActive === active ? "skip" : "syncActive";
}

async function writeEmbedding(
  id: string, listing: ListingLike & { isActive?: unknown }, vector: number[]
): Promise<void> {
  await admin.firestore().collection("listingEmbeddings").doc(id).set({
    embedding: admin.firestore.FieldValue.vector(vector),
    hash: embeddingHash(listingEmbeddingText(listing)),
    isActive: listing.isActive !== false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/** Κρατά το embedding συγχρονισμένο με κάθε αλλαγή αγγελίας. */
export const embedListing = onDocumentWritten(
  {
    document: "listings/{id}",
    secrets: [GEMINI_API_KEY],
    maxInstances: 3,
  },
  async (event) => {
    const id = event.params.id;
    const listing = event.data?.after?.data();
    const ref = admin.firestore().collection("listingEmbeddings").doc(id);
    const existing = listing ? (await ref.get()).data() : undefined;

    switch (embeddingAction(listing, existing)) {
    case "delete":
      await ref.delete();
      return;
    case "syncActive":
      await ref.update({ isActive: listing?.isActive !== false });
      return;
    case "skip":
      return;
    case "embed":
      try {
        const [vector] = await embedTexts([listingEmbeddingText(listing!)]);
        await writeEmbedding(id, listing!, vector);
      } catch (e) {
        // Π.χ. 429 (όριο ανά λεπτό). ΔΕΝ ξαναπροσπαθούμε εδώ: το
        // embedMissingListings το πιάνει στην επόμενη εκτέλεσή του.
        logger.warn(`embedListing ${id} failed`, e);
      }
    }
  }
);

/**
 * Ασφάλεια: συμπληρώνει embeddings που λείπουν ή είναι παλιά — αγγελίες από
 * ΠΡΙΝ το feature, ή αποτυχίες του trigger (όριο ανά λεπτό, σφάλμα δικτύου).
 * Ανά εκτέλεση έως [BATCH] αγγελίες, κάτω από το δωρεάν όριο (100/λεπτό).
 */
export const embedMissingListings = onSchedule(
  {
    schedule: "every 6 hours",
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 300,
  },
  async () => {
    const BATCH = 40;
    const db = admin.firestore();
    const listings = await db.collection("listings")
      .where("isActive", "==", true)
      .orderBy("createdAt", "desc")
      .limit(500)
      .get();
    if (listings.empty) return;

    const embRefs = listings.docs.map((d) =>
      db.collection("listingEmbeddings").doc(d.id));
    const existing = await db.getAll(...embRefs);

    const todo = listings.docs
      .filter((d, i) =>
        embeddingAction(d.data(), existing[i].data()) !== "skip")
      .slice(0, BATCH);
    logger.info(`embedMissingListings: ${todo.length} to embed`);

    for (let i = 0; i < todo.length; i += 20) {
      const chunk = todo.slice(i, i + 20);
      const vectors = await embedTexts(
        chunk.map((d) => listingEmbeddingText(d.data())));
      await Promise.all(chunk.map((d, j) =>
        writeEmbedding(d.id, d.data(), vectors[j])));
    }
  }
);
