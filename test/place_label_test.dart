import 'package:flutter_test/flutter_test.dart';
import 'package:shareit/core/utils/place_label.dart';

void main() {
  group('isPlaceholder — αναγνωρίζει «μη-τόπους»', () {
    test('κενό / whitespace / null', () {
      expect(PlaceLabel.isPlaceholder(''), isTrue);
      expect(PlaceLabel.isPlaceholder('   '), isTrue);
      expect(PlaceLabel.isPlaceholder(null), isTrue);
    });

    test('τα ΕΛΛΗΝΙΚΑ sentinels παλιών αγγελιών (ΜΗΝ τα αφαιρέσεις)', () {
      // Υπάρχουν ακόμα στη βάση από προηγούμενες εκδόσεις.
      expect(PlaceLabel.isPlaceholder('Τρέχουσα τοποθεσία'), isTrue);
      expect(PlaceLabel.isPlaceholder('Επιλεγμένη τοποθεσία'), isTrue);
      expect(PlaceLabel.isPlaceholder('Δεν βρέθηκε τοποθεσία'), isTrue);
    });

    test('πραγματικός τόπος ΔΕΝ είναι placeholder', () {
      expect(PlaceLabel.isPlaceholder('Κασσώπης, Πρέβεζα'), isFalse);
      expect(PlaceLabel.isPlaceholder('Αθήνα'), isFalse);
      expect(PlaceLabel.isPlaceholder('Ioannina'), isFalse);
    });
  });

  group('toStore — τι γράφεται στη βάση', () {
    test('placeholder → ΚΕΝΟ (ποτέ κείμενο εμφάνισης)', () {
      // Αυτό αποτρέπει (α) ελληνικά σε ξενόγλωσσο UI και (β) μόλυνση της
      // αναζήτησης, αφού το locationLabel μπαίνει στα searchKeywords.
      expect(PlaceLabel.toStore('Επιλεγμένη τοποθεσία'), '');
      expect(PlaceLabel.toStore(null), '');
      expect(PlaceLabel.toStore('  '), '');
    });

    test('πραγματικός τόπος αποθηκεύεται αυτούσιος (trimmed)', () {
      expect(PlaceLabel.toStore('  Κασσώπης, Πρέβεζα '), 'Κασσώπης, Πρέβεζα');
    });

    test('η λέξη «τοποθεσία» δεν καταλήγει ποτέ στο index', () {
      for (final p in PlaceLabel.placeholders) {
        expect(PlaceLabel.toStore(p), '');
      }
    });
  });
}
