# Firestore rules tests

Ελέγχει ότι (α) οι επιθέσεις απορρίπτονται και (β) κάθε κανονική λειτουργία της
εφαρμογής εξακολουθεί να δουλεύει. Τρέξ' τα ΠΡΙΝ από κάθε `firebase deploy --only firestore:rules`.

```bash
cd firestore-tests
npm install
npm test
```

Απαιτεί JDK 21+ (ο Firestore emulator). Με JDK 17:
`npx firebase-tools@13 emulators:exec --only firestore --project demo-shareit "node rules.test.mjs"`
