import 'package:easy_localization/easy_localization.dart';

/// Κοινή, μεταφρασμένη λίστα χωρών για τους country pickers (κινητό/OTP).
/// Κρατά το ίδιο σχήμα `Map<String, String>` ({code, flag, name}) που περιμένουν
/// οι οθόνες, ώστε να μην αλλάζει ο κώδικας χρήσης. Το `name` είναι ήδη
/// μεταφρασμένο μέσω `.tr()`, και επειδή είναι getter επαναϋπολογίζεται σε κάθε
/// build — άρα ενημερώνεται αυτόματα όταν αλλάζει η γλώσσα.
class Countries {
  static List<Map<String, String>> get all => [
        {'code': '+30', 'flag': '🇬🇷', 'name': 'countries.gr'.tr()},
        {'code': '+357', 'flag': '🇨🇾', 'name': 'countries.cy'.tr()},
        {'code': '+46', 'flag': '🇸🇪', 'name': 'countries.se'.tr()},
        {'code': '+47', 'flag': '🇳🇴', 'name': 'countries.no'.tr()},
        {'code': '+45', 'flag': '🇩🇰', 'name': 'countries.dk'.tr()},
        {'code': '+358', 'flag': '🇫🇮', 'name': 'countries.fi'.tr()},
        {'code': '+49', 'flag': '🇩🇪', 'name': 'countries.de'.tr()},
        {'code': '+33', 'flag': '🇫🇷', 'name': 'countries.fr'.tr()},
        {'code': '+39', 'flag': '🇮🇹', 'name': 'countries.it'.tr()},
        {'code': '+34', 'flag': '🇪🇸', 'name': 'countries.es'.tr()},
        {'code': '+31', 'flag': '🇳🇱', 'name': 'countries.nl'.tr()},
        {'code': '+32', 'flag': '🇧🇪', 'name': 'countries.be'.tr()},
        {'code': '+41', 'flag': '🇨🇭', 'name': 'countries.ch'.tr()},
        {'code': '+43', 'flag': '🇦🇹', 'name': 'countries.at'.tr()},
        {'code': '+355', 'flag': '🇦🇱', 'name': 'countries.al'.tr()},
        {'code': '+44', 'flag': '🇬🇧', 'name': 'countries.gb'.tr()},
        {'code': '+1', 'flag': '🇺🇸', 'name': 'countries.us'.tr()},
        {'code': '+1', 'flag': '🇨🇦', 'name': 'countries.ca'.tr()},
        {'code': '+61', 'flag': '🇦🇺', 'name': 'countries.au'.tr()},
      ];
}
