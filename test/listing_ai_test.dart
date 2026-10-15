import 'package:flutter_test/flutter_test.dart';
import 'package:shareit/core/services/ai_functions.dart';
import 'package:shareit/features/listings/data/listing_ai_service.dart';
import 'package:shareit/features/listings/data/listing_model.dart';
import 'package:shareit/features/search/data/search_ai_service.dart';

/// Καταγράφει ποιο callable κλήθηκε και με τι — χωρίς Firebase.
class _FakeFunctions extends AiFunctions {
  _FakeFunctions({this.response = const {}, this.failure});
  final Map<String, dynamic> response;
  final AiFailure? failure;
  String? name;
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    this.name = name;
    this.data = data;
    if (failure != null) throw AiException(failure!);
    return response;
  }
}

const _drill = ListingSuggestion(
  suitable: true,
  title: 'Δράπανο μπαταρίας',
  description: 'Σε καλή κατάσταση, με δύο μπαταρίες.',
  category: ListingCategory.tools,
  tags: ['δράπανο', 'εργαλεία', 'diy'],
);

void main() {
  group('ListingSuggestion.fromMap', () {
    test('διαβάζει την απάντηση του server', () {
      final s = ListingSuggestion.fromMap({
        'suitable': true,
        'title': ' Δράπανο ',
        'description': 'Καλή κατάσταση.',
        'category': 'tools',
        'tags': ['δράπανο', 7, ' '],
      });
      expect(s.suitable, isTrue);
      expect(s.title, 'Δράπανο');
      expect(s.category, ListingCategory.tools);
      expect(s.tags, ['δράπανο']);
    });

    test('suitable=false → αγνοεί ό,τι άλλο ήρθε', () {
      final s = ListingSuggestion.fromMap({
        'suitable': false,
        'title': 'κάτι',
        'category': 'tools',
        'tags': ['a'],
      });
      expect(s.suitable, isFalse);
      expect(s.title, isEmpty);
      expect(s.category, isNull);
      expect(s.tags, isEmpty);
    });

    test('κενή/χαλασμένη απάντηση → μη κατάλληλη, χωρίς throw', () {
      expect(ListingSuggestion.fromMap({}).suitable, isFalse);
      expect(
          ListingSuggestion.fromMap({'suitable': 'yes', 'tags': 'x'}).suitable,
          isFalse);
    });
  });

  group('ListingDraft.fillFrom', () {
    test('άδεια φόρμα → γεμίζει όλα τα πεδία', () {
      final d = const ListingDraft().fillFrom(_drill, maxTags: 5);
      expect(d.title, 'Δράπανο μπαταρίας');
      expect(d.description, startsWith('Σε καλή'));
      expect(d.category, ListingCategory.tools);
      expect(d.tags, ['δράπανο', 'εργαλεία', 'diy']);
    });

    test('ΔΕΝ σβήνει ό,τι έγραψε ήδη ο χρήστης', () {
      final d = const ListingDraft(
        title: 'Το τρυπάνι μου',
        category: ListingCategory.other,
      ).fillFrom(_drill, maxTags: 5);
      expect(d.title, 'Το τρυπάνι μου');
      expect(d.category, ListingCategory.other);
      // Η περιγραφή ήταν κενή → συμπληρώνεται.
      expect(d.description, isNotEmpty);
    });

    test('τίτλος μόνο με κενά θεωρείται άδειος', () {
      final d = const ListingDraft(title: '   ').fillFrom(_drill, maxTags: 5);
      expect(d.title, 'Δράπανο μπαταρίας');
    });

    test('tags: προσθήκη χωρίς διπλά, έως το όριο', () {
      final d = const ListingDraft(tags: ['εργαλεία', 'bosch', 'μπαταρία'])
          .fillFrom(_drill, maxTags: 5);
      expect(d.tags, ['εργαλεία', 'bosch', 'μπαταρία', 'δράπανο', 'diy']);
    });

    test('μη κατάλληλη πρόταση → η φόρμα μένει ίδια', () {
      const before = ListingDraft(title: 'x', tags: ['a']);
      final after = before.fillFrom(
          const ListingSuggestion(suitable: false), maxTags: 5);
      expect(identical(after, before), isTrue);
    });
  });

  group('services → callables', () {
    test('ListingAiService στέλνει path, τύπο και γλώσσα', () async {
      final fn = _FakeFunctions(response: {
        'suitable': true,
        'title': 'Σκηνή',
        'description': '',
        'category': 'sports',
        'tags': ['σκηνή'],
      });
      final s = await ListingAiService(ai: fn).suggestFromImage(
        storagePath: 'listings/u1/1_a.jpg',
        type: ListingType.seek,
        locale: 'el',
      );
      expect(fn.name, 'suggestListingFromImage');
      expect(fn.data, {
        'storagePath': 'listings/u1/1_a.jpg',
        'type': 'seek',
        'locale': 'el',
      });
      expect(s.category, ListingCategory.sports);
    });

    test('SearchAiService καλεί parseSearchQuery', () async {
      final fn = _FakeFunctions(response: {
        'keywords': ['σκηνή'],
        'type': null,
        'category': 'sports',
        'maxDistanceKm': null,
        'availableFrom': null,
        'availableUntil': null,
        'sort': null,
      });
      final f = await SearchAiService(ai: fn).parse('σκηνή για κάμπινγκ');
      expect(fn.name, 'parseSearchQuery');
      expect(fn.data, {'query': 'σκηνή για κάμπινγκ'});
      expect(f.category, ListingCategory.sports);
    });

    test('τα σφάλματα φτάνουν ως AiException με τον λόγο', () async {
      final fn = _FakeFunctions(failure: AiFailure.quota);
      expect(
        () => ListingAiService(ai: fn).suggestFromImage(
            storagePath: 'p', type: ListingType.offer, locale: 'el'),
        throwsA(isA<AiException>()
            .having((e) => e.reason, 'reason', AiFailure.quota)),
      );
    });
  });
}
