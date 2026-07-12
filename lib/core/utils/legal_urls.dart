/// Οι διευθύνσεις των νομικών κειμένων, στη γλώσσα του χρήστη.
///
/// Τα κείμενα υπάρχουν σε ελληνικά (προεπιλογή), αγγλικά και ισπανικά — όσες
/// γλώσσες υποστηρίζει η εφαρμογή. Κάθε σελίδα έχει και εναλλαγή γλώσσας, οπότε
/// ακόμα κι αν πέσει κάποιος σε λάθος έκδοση, μπορεί να αλλάξει.
class LegalUrls {
  LegalUrls._();

  static const _base = 'https://shareit-6cfa0.web.app';

  static String _suffix(String languageCode) {
    switch (languageCode) {
      case 'en':
        return '_en';
      case 'es':
        return '_es';
      default:
        return ''; // ελληνικά
    }
  }

  static String privacy(String languageCode) =>
      '$_base/privacy_policy${_suffix(languageCode)}.html';

  static String terms(String languageCode) =>
      '$_base/terms${_suffix(languageCode)}.html';

  /// Η σελίδα διαγραφής λογαριασμού (μόνο ελληνικά προς το παρόν — η in-app
  /// διαγραφή είναι ο κύριος δρόμος και είναι μεταφρασμένη).
  static const deleteAccount = '$_base/delete-account.html';
}
