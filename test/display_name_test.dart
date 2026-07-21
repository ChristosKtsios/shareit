import 'package:flutter_test/flutter_test.dart';
import 'package:shareit/core/utils/display_name.dart';

void main() {
  group('Google sign-in: από πού βγαίνει όνομα/επώνυμο', () {
    test('1η επιλογή: το displayName του Google', () {
      final (f, l) = DisplayName.from(
          displayName: 'Γιώργος Παπαδόπουλος', email: 'giorgos@gmail.com');
      expect(f, 'Γιώργος');
      expect(l, 'Παπαδόπουλος');
    });

    test('το email ΑΓΝΟΕΙΤΑΙ όταν υπάρχει displayName', () {
      final (f, _) = DisplayName.from(
          displayName: 'Μαρία Λάμπρου', email: 'totally.different@gmail.com');
      expect(f, 'Μαρία'); // όχι «Totally»
    });

    test('2η επιλογή (fallback): χωρίς displayName → από το email', () {
      final (f, l) =
          DisplayName.from(displayName: null, email: 'giorgos.pap@gmail.com');
      expect(f, 'Giorgos');
      expect(l, 'Pap');
    });

    test('fallback: υποστηρίζει . _ - + ως διαχωριστικά', () {
      expect(DisplayName.from(email: 'maria_lambrou@x.com'), ('Maria', 'Lambrou'));
      expect(DisplayName.from(email: 'nikos-petrou@x.com'), ('Nikos', 'Petrou'));
    });

    test('fallback: κόβει αριθμούς («giorgos90» → «Giorgos»)', () {
      final (f, _) = DisplayName.from(email: 'giorgos90@gmail.com');
      expect(f, 'Giorgos');
    });

    test('fallback: σκέτο όνομα χωρίς επώνυμο → κενό επώνυμο', () {
      final (f, l) = DisplayName.from(email: 'giorgos@gmail.com');
      expect(f, 'Giorgos');
      expect(l, '');
    });

    test('ούτε displayName ούτε email → κενά (ζητά συμπλήρωση προφίλ)', () {
      expect(DisplayName.from(), ('', ''));
    });
  });
}
