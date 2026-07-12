/// Παράγει όνομα/επώνυμο για έναν χρήστη που συνδέθηκε με Google.
///
/// Σειρά προτίμησης:
///   1. Το `displayName` του λογαριασμού Google («Γιώργος Παπαδόπουλος»)
///   2. Το τοπικό μέρος του email του ΙΔΙΟΥ του χρήστη («giorgos.pap» → «Giorgos Pap»)
///
/// Το email διαβάζεται από το **Firebase Auth** (δικό του δεδομένο), ΟΧΙ από το
/// Firestore — τα emails άλλων χρηστών δεν είναι αναγνώσιμα. Χωρίς αυτό το
/// fallback, όποιος λογαριασμός Google δεν έχει displayName εμφανιζόταν ως
/// σκέτο «Χρήστης».
class DisplayName {
  /// Επιστρέφει `(firstName, lastName)`. Μπορεί να είναι κενά αν δεν υπάρχει
  /// ούτε displayName ούτε email — τότε ο χρήστης θα κληθεί να συμπληρώσει
  /// προφίλ.
  static (String, String) from({String? displayName, String? email}) {
    final dn = (displayName ?? '').trim();
    if (dn.isNotEmpty) return _split(dn);

    final local = (email ?? '').split('@').first.trim();
    if (local.isEmpty) return ('', '');

    // «giorgos.papadopoulos», «giorgos_pap», «giorgos-pap» → «Giorgos Pap»
    final words = local
        .split(RegExp(r'[._\-+]+'))
        .where((w) => w.isNotEmpty)
        // Σκέτοι αριθμοί (π.χ. «giorgos1990») δεν είναι όνομα.
        .where((w) => !RegExp(r'^\d+$').hasMatch(w))
        .map(_capitalize)
        .toList();

    if (words.isEmpty) return ('', '');
    return _split(words.join(' '));
  }

  static (String, String) _split(String full) {
    final parts = full.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return ('', '');
    final first = parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return (first, last);
  }

  static String _capitalize(String w) {
    // Αφαίρεσε τυχόν αριθμούς στο τέλος: «giorgos90» → «Giorgos»
    final clean = w.replaceAll(RegExp(r'\d+$'), '');
    if (clean.isEmpty) return '';
    return clean[0].toUpperCase() + clean.substring(1);
  }
}
