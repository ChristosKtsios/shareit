import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shareit/features/listings/data/listing_model.dart';
import 'package:shareit/features/listings/data/listing_repository.dart';

/// Φτιάχνει αγγελία ακριβώς όπως στην παραγωγή: τα keywords βγαίνουν από
/// τίτλο + περιγραφή + tags + τοποθεσία.
ListingModel _l(
  String title,
  String desc, {
  List<String> tags = const [],
  String locationLabel = 'Αθήνα',
  List<String> images = const [],
}) =>
    ListingModel(
      id: title,
      userId: 'u',
      userFirstName: 'Χ',
      type: ListingType.offer,
      title: title,
      description: desc,
      locationLabel: locationLabel,
      tags: tags,
      imageUrls: images,
      searchKeywords: ListingModel.generateKeywords(title, desc,
          tags: tags, locationLabel: locationLabel),
      location: const GeoPoint(37.98, 23.72),
      autoDelete: false,
      isActive: true,
      rating: 0,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('tokenize', () {
    test('αφαιρεί τόνους και πεζοποιεί', () {
      expect(ListingModel.tokenize('Τρυπάνι'), ['τρυπανι']);
      expect(ListingModel.tokenize('ΨΗΣΤΑΡΙΆ'), ['ψησταρια']);
    });

    test('τελικό ς γίνεται σ (ώστε «γάτας» = «γατασ»)', () {
      expect(ListingModel.tokenize('γάτας'), ['γατασ']);
    });

    test('κόβει λέξεις ≤2 χαρακτήρων', () {
      expect(ListingModel.tokenize('το να με'), isEmpty);
      expect(ListingModel.tokenize('ένα τρυπάνι'), contains('τρυπανι'));
      expect(ListingModel.tokenize('ένα τρυπάνι'), isNot(contains('το')));
    });

    test('σημεία στίξης χωρίζουν λέξεις (δεν τις κολλάνε)', () {
      final t = ListingModel.tokenize('σκάλα,ξύλινη');
      expect(t, containsAll(['σκαλα', 'ξυλινη']));
    });

    test('χωρίς διπλότυπα', () {
      final t = ListingModel.tokenize('τρυπάνι τρυπανι ΤΡΥΠΆΝΙ');
      expect(t.where((w) => w == 'τρυπανι').length, 1);
    });
  });

  group('generateKeywords — αποθηκεύει ΚΑΙ τις δύο μορφές', () {
    test('περιέχει την άτονη (για τη νέα αναζήτηση)', () {
      final k = ListingModel.generateKeywords('Τρυπάνι', '');
      expect(k, contains('τρυπανι'));
    });

    test('περιέχει και την ΤΟΝΙΣΜΕΝΗ (συμβατότητα με παλιά έκδοση app)', () {
      // Η παλιά έκδοση κάνει arrayContains('τρυπάνι') — αν λείψει η τονισμένη
      // μορφή, σπάει η αναζήτηση σε όσους δεν έχουν ενημερωθεί.
      final k = ListingModel.generateKeywords('Τρυπάνι', '');
      expect(k, contains('τρυπάνι'));
    });

    test('άτονη λέξη δεν αποθηκεύεται δύο φορές', () {
      final k = ListingModel.generateKeywords('ποδηλατο', '');
      expect(k.where((w) => w == 'ποδηλατο').length, 1);
    });
  });

  group('queryTokens — ίδια μορφή με τα keywords της αγγελίας', () {
    test('άτονο ερώτημα ταιριάζει με τονισμένη αγγελία', () {
      final listing = _l('Τρυπάνι Bosch', 'Δανείζω κρουστικό τρυπάνι');
      // Ο χρήστης γράφει ΧΩΡΙΣ τόνο:
      final tokens = ListingRepository.queryTokens('τρυπανι');
      expect(ListingRepository.relevance(listing, tokens), greaterThan(0));
    });

    test('κόβεται στα 30 tokens (όριο Firestore arrayContainsAny)', () {
      final many = List.generate(40, (i) => 'λεξη$i').join(' ');
      expect(ListingRepository.queryTokens(many).length, 30);
    });
  });

  group('#1 tags & τοποθεσία είναι αναζητήσιμα', () {
    final l = _l('Ψησταριά', 'Για μπάρμπεκιου',
        tags: ['κηπος', 'εκδηλωσεις'], locationLabel: 'Νέος Κόσμος, Αθήνα');

    test('το tag που βλέπει ο χρήστης στην κάρτα το βρίσκει', () {
      // Πριν: ο τίτλος έλεγε «Ψησταριά», το tag «#κηπος» δεν ήταν πουθενά στα
      // keywords → αναζήτηση «κηπος» = 0 αποτελέσματα.
      final t = ListingRepository.queryTokens('κηπος');
      expect(ListingRepository.relevance(l, t), greaterThan(0));
    });

    test('η πόλη είναι αναζητήσιμη', () {
      final t = ListingRepository.queryTokens('Αθήνα');
      expect(ListingRepository.relevance(l, t), greaterThan(0));
    });

    test('η τοποθεσία δουλεύει και άτονη', () {
      final t = ListingRepository.queryTokens('αθηνα');
      expect(ListingRepository.relevance(l, t), greaterThan(0));
    });

    test('άσχετη λέξη δεν ταιριάζει', () {
      final t = ListingRepository.queryTokens('τρυπανι');
      expect(ListingRepository.relevance(l, t), 0);
    });
  });

  group('#2 ranking: ο τίτλος βαραίνει περισσότερο', () {
    final inTitle = _l('Τρυπάνι Bosch', 'Δανείζω εργαλείο');
    final inDesc = _l('Εργαλειοθήκη', 'Περιέχει και ένα τρυπάνι');

    test('όρος στον τίτλο δίνει περισσότερους πόντους από ό,τι στην περιγραφή',
        () {
      final t = ListingRepository.queryTokens('τρυπανι');
      final sTitle = ListingRepository.relevance(inTitle, t);
      final sDesc = ListingRepository.relevance(inDesc, t);
      expect(sTitle, greaterThan(sDesc));
      expect(sDesc, greaterThan(0)); // αλλά εμφανίζεται κι αυτή
    });

    test('ταξινόμηση: η αγγελία με τον όρο στον τίτλο μπαίνει πρώτη', () {
      final t = ListingRepository.queryTokens('τρυπανι');
      final list = [inDesc, inTitle]; // σκόπιμα ανάποδα
      list.sort((a, b) => ListingRepository.relevance(b, t)
          .compareTo(ListingRepository.relevance(a, t)));
      expect(list.first.title, 'Τρυπάνι Bosch');
    });
  });

  group('#2 αναζήτηση με ΜΕΡΟΣ λέξης (προθέματα τίτλου)', () {
    final drill = _l('Τρυπάνι Bosch', 'Κρουστικό εργαλείο');

    test('«τρυπ» βρίσκει το «Τρυπάνι» (πριν: 0 αποτελέσματα)', () {
      expect(drill.searchKeywords, contains('τρυπ'));
      final t = ListingRepository.queryTokens('τρυπ');
      expect(ListingRepository.relevance(drill, t), greaterThan(0));
    });

    test('προθέματα από 3 χαρακτήρες και πάνω', () {
      expect(drill.searchKeywords, contains('τρυ'));
      expect(drill.searchKeywords, isNot(contains('τρ'))); // πολύ κοντό
    });

    test('πρόθεμα τίτλου παίρνει τη βαρύτητα του ΤΙΤΛΟΥ', () {
      final inTitle = _l('Τρυπάνι Bosch', 'χωρίς άλλη λέξη');
      final inDesc = _l('Εργαλειοθήκη', 'έχει ένα τρυπάνι μέσα');
      final t = ListingRepository.queryTokens('τρυπ');
      expect(ListingRepository.relevance(inTitle, t),
          greaterThan(ListingRepository.relevance(inDesc, t)));
    });

    test('ΔΕΝ φτιάχνονται προθέματα από την περιγραφή (κόστος δεδομένων)', () {
      final l = _l('Ποδήλατο', 'κρουστικό τρυπανι');
      expect(l.searchKeywords, contains('ποδ')); // τίτλος ✅
      expect(l.searchKeywords, isNot(contains('κρου'))); // περιγραφή ❌
    });
  });

  group('#3 αγγελίες ΜΕ φωτογραφία ανεβαίνουν', () {
    test('με ίδια σχετικότητα, αυτή με φωτό είναι πρώτη', () {
      final withPhoto = _l('Τρυπάνι', 'a', images: ['https://x/1.jpg']);
      final noPhoto = _l('Τρυπάνι', 'a');
      final t = ListingRepository.queryTokens('τρυπανι');
      expect(ListingRepository.relevance(withPhoto, t),
          greaterThan(ListingRepository.relevance(noPhoto, t)));
    });

    test('το μπόνους ΔΕΝ εμφανίζει άσχετη αγγελία', () {
      final irrelevant = _l('Ποδήλατο', 'a', images: ['https://x/1.jpg']);
      final t = ListingRepository.queryTokens('τρυπανι');
      expect(ListingRepository.relevance(irrelevant, t), 0);
    });

    test('η ΠΙΟ ΣΧΕΤΙΚΗ χωρίς φωτό νικά λιγότερο σχετική με φωτό', () {
      // Το μπόνους σπάει ισοπαλίες — δεν θάβει τη σχετικότητα.
      final relevantNoPhoto = _l('Τρυπάνι Bosch', 'a');
      final lessRelevantPhoto = _l('Εργαλεία', 'ένα τρυπάνι', images: ['x']);
      final t = ListingRepository.queryTokens('τρυπανι bosch');
      expect(ListingRepository.relevance(relevantNoPhoto, t),
          greaterThan(ListingRepository.relevance(lessRelevantPhoto, t)));
    });
  });

  group('relevance — περισσότερες λέξεις = πιο ψηλά', () {
    final drill = _l('Τρυπάνι Bosch', 'Κρουστικό τρυπάνι με σετ μύτες');
    final bike = _l('Ποδήλατο πόλης', 'Αστικό ποδήλατο με καλάθι');

    test('όσο περισσότεροι όροι ταιριάζουν, τόσο μεγαλύτερο σκορ', () {
      final both = ListingRepository.queryTokens('τρυπάνι bosch'); // 2 όροι
      final one = ListingRepository.queryTokens('τρυπάνι'); // 1 όρος
      expect(ListingRepository.relevance(drill, both),
          greaterThan(ListingRepository.relevance(drill, one)));
      expect(ListingRepository.relevance(bike, both), 0); // άσχετη → μηδέν
    });

    test('OR: κάθε αγγελία με ΜΙΑ κοινή λέξη εμφανίζεται (σκορ > 0)', () {
      final tokens = ListingRepository.queryTokens('τρυπάνι ποδήλατο');
      expect(ListingRepository.relevance(drill, tokens), greaterThan(0));
      expect(ListingRepository.relevance(bike, tokens), greaterThan(0));
    });

    test('ταξινόμηση: το πιο σχετικό πρώτο', () {
      final tokens = ListingRepository.queryTokens('τρυπανι bosch καλαθι');
      final list = [bike, drill]; // σκόπιμα ανάποδα
      list.sort((a, b) => ListingRepository.relevance(b, tokens)
          .compareTo(ListingRepository.relevance(a, tokens)));
      expect(list.first.title, 'Τρυπάνι Bosch'); // 2 matches > 1 match
    });

    test('κενοί όροι → score 0', () {
      expect(ListingRepository.relevance(drill, []), 0);
    });
  });
}
