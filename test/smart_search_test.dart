import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shareit/core/services/ai_functions.dart';
import 'package:shareit/features/listings/data/listing_model.dart';
import 'package:shareit/features/listings/data/listing_repository.dart';
import 'package:shareit/features/search/data/search_ai_service.dart';
import 'package:shareit/features/search/providers/search_provider.dart';

ListingModel _l(
  String title, {
  ListingType type = ListingType.offer,
  ListingCategory? category,
  DateTime? from,
  DateTime? until,
  DateTime? createdAt,
}) =>
    ListingModel(
      id: title,
      userId: 'u',
      userFirstName: 'Χ',
      type: type,
      category: category,
      title: title,
      description: '',
      locationLabel: 'Αθήνα',
      searchKeywords: ListingModel.generateKeywords(title, ''),
      location: const GeoPoint(37.98, 23.72),
      availableFrom: from,
      availableUntil: until,
      autoDelete: false,
      isActive: true,
      rating: 0,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
    );

/// Καταγράφει με ΠΟΙΑ φίλτρα κλήθηκε το repository — χωρίς Firestore.
class _FakeRepo extends ListingRepository {
  _FakeRepo(this.results, {this.byId = const {}});
  final List<ListingModel> results;

  /// «Βάση» για τα σημασιολογικά ids (getActiveByIds).
  final Map<String, ListingModel> byId;
  final calls = <Map<String, Object?>>[];
  final idCalls = <List<String>>[];

  @override
  Future<List<ListingModel>> getActiveByIds(Iterable<String> ids) async {
    idCalls.add(ids.toList());
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }

  @override
  Future<List<ListingModel>> search({
    required String keyword,
    Set<String> tags = const {},
    ListingType? type,
    ListingCategory? category,
    DateTime? availableFrom,
    DateTime? availableUntil,
  }) async {
    calls.add({
      'keyword': keyword,
      'type': type,
      'category': category,
      'from': availableFrom,
      'until': availableUntil,
    });
    return results;
  }
}

class _FakeAi extends SearchAiService {
  _FakeAi({this.filters, this.failure});
  final AiSearchFilters? filters;
  final AiFailure? failure;
  final queries = <String>[];

  @override
  Future<AiSearchFilters> parse(String query) async {
    queries.add(query);
    if (failure != null) throw AiException(failure!);
    return filters!;
  }
}

void main() {
  group('AiSearchFilters.fromMap', () {
    test('διαβάζει όλα τα πεδία του server', () {
      final f = AiSearchFilters.fromMap({
        'keywords': ['ποδήλατο', 'ποδηλατο παιδικό'],
        'type': 'offer',
        'category': 'kids',
        'maxDistanceKm': 5,
        'availableFrom': '2026-10-10',
        'availableUntil': '2026-10-11',
        'sort': 'nearest',
      });
      expect(f.keywords, ['ποδήλατο', 'ποδηλατο παιδικό']);
      expect(f.type, ListingType.offer);
      expect(f.category, ListingCategory.kids);
      expect(f.maxDistanceKm, 5.0);
      expect(f.availableFrom, DateTime(2026, 10, 10));
      expect(f.availableUntil, DateTime(2026, 10, 11));
      expect(f.sortNearest, isTrue);
    });

    test('άγνωστες/κακές τιμές γίνονται null — ποτέ throw', () {
      final f = AiSearchFilters.fromMap({
        'keywords': ['ok', 42, '  '],
        'type': 'rent',
        'category': 'spaceships',
        'maxDistanceKm': null,
        'availableFrom': 'αύριο',
        'sort': null,
      });
      expect(f.keywords, ['ok']);
      expect(f.type, isNull);
      expect(f.category, isNull);
      expect(f.maxDistanceKm, isNull);
      expect(f.availableFrom, isNull);
      expect(f.sortNearest, isFalse);
    });

    test('κενός χάρτης → κενά φίλτρα', () {
      final f = AiSearchFilters.fromMap({});
      expect(f.keywords, isEmpty);
      expect(f.type, isNull);
    });
  });

  group('isAvailableBetween', () {
    final sat = DateTime(2026, 10, 10);
    final sun = DateTime(2026, 10, 11);

    test('χωρίς όρια διαθεσιμότητας → πάντα διαθέσιμη', () {
      expect(ListingRepository.isAvailableBetween(_l('a'), sat, sun), isTrue);
    });

    test('λήγει ΠΡΙΝ το παράθυρο → όχι', () {
      final l = _l('a', until: DateTime(2026, 10, 9));
      expect(ListingRepository.isAvailableBetween(l, sat, sun), isFalse);
    });

    test('αρχίζει ΜΕΤΑ το παράθυρο → όχι', () {
      final l = _l('a', from: DateTime(2026, 10, 12));
      expect(ListingRepository.isAvailableBetween(l, sat, sun), isFalse);
    });

    test('επικάλυψη έστω μίας ημέρας → ναι', () {
      final l = _l('a',
          from: DateTime(2026, 10, 1), until: DateTime(2026, 10, 10));
      expect(ListingRepository.isAvailableBetween(l, sat, sun), isTrue);
    });

    test('λήγει ίδια μέρα νωρίς το πρωί → μετράει (σύγκριση ανά ημέρα)', () {
      final l = _l('a', until: DateTime(2026, 10, 10, 8));
      expect(
          ListingRepository.isAvailableBetween(
              l, DateTime(2026, 10, 10, 18), null),
          isTrue);
    });
  });

  group('SearchNotifier', () {
    test('χωρίς κριτήρια δεν καλεί καν το repository', () async {
      final repo = _FakeRepo([_l('Τρυπάνι')]);
      final n = SearchNotifier(repository: repo, ai: _FakeAi());
      await n.search('   ');
      expect(repo.calls, isEmpty);
      expect(n.state.results, isEmpty);
    });

    test('η κατηγορία από μόνη της είναι κριτήριο', () async {
      final repo = _FakeRepo([_l('Κατσαβίδι', category: ListingCategory.tools)]);
      final n = SearchNotifier(repository: repo, ai: _FakeAi());
      n.setCategory(ListingCategory.tools);
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls.single['category'], ListingCategory.tools);
      expect(n.state.results, hasLength(1));
    });

    test('smartSearch: τα φίλτρα του AI περνούν στην αναζήτηση', () async {
      final repo = _FakeRepo([_l('Παιδικό ποδήλατο')]);
      final ai = _FakeAi(
        filters: AiSearchFilters(
          keywords: const ['ποδήλατο', 'παιδικό'],
          type: ListingType.offer,
          category: ListingCategory.kids,
          maxDistanceKm: 5,
          availableFrom: DateTime(2026, 10, 10),
          availableUntil: DateTime(2026, 10, 10),
        ),
      );
      final n = SearchNotifier(
          repository: repo, ai: ai, locate: () async => null);

      await n.smartSearch('ψάχνω παιδικό ποδήλατο κοντά μου το Σάββατο');

      expect(ai.queries.single,
          'ψάχνω παιδικό ποδήλατο κοντά μου το Σάββατο');
      final call = repo.calls.single;
      expect(call['keyword'], 'ποδήλατο παιδικό');
      expect(call['type'], ListingType.offer);
      expect(call['category'], ListingCategory.kids);
      expect(call['from'], DateTime(2026, 10, 10));
      expect(n.state.distanceKm, 5);
      expect(n.state.aiApplied, isTrue);
      expect(n.state.aiLoading, isFalse);
      expect(n.state.results, hasLength(1));
    });

    test('smartSearch: αν το AI αποτύχει, γίνεται απλή αναζήτηση', () async {
      final repo = _FakeRepo([_l('Τρυπάνι')]);
      final n = SearchNotifier(
        repository: repo,
        ai: _FakeAi(failure: AiFailure.unavailable),
      );

      await n.smartSearch('τρυπάνι');

      expect(repo.calls.single['keyword'], 'τρυπάνι');
      expect(n.state.aiApplied, isFalse);
      expect(n.state.notice, isNotNull);
      expect(n.state.results, hasLength(1));
    });

    test('smartSearch: τα φίλτρα AI αντικαθιστούν τα προηγούμενα', () async {
      final repo = _FakeRepo([]);
      final n = SearchNotifier(
        repository: repo,
        ai: _FakeAi(filters: const AiSearchFilters(keywords: ['σκηνή'])),
      );
      n.setType(ListingType.seek);
      n.setCategory(ListingCategory.tools);
      await Future<void>.delayed(Duration.zero);

      await n.smartSearch('σκηνή για κάμπινγκ');

      expect(n.state.type, isNull);
      expect(n.state.category, isNull);
      expect(repo.calls.last['keyword'], 'σκηνή');
    });

    test('clearFilters καθαρίζει και την ένδειξη AI', () async {
      final repo = _FakeRepo([]);
      final n = SearchNotifier(
        repository: repo,
        ai: _FakeAi(
            filters: const AiSearchFilters(
                keywords: ['βιβλίο'], category: ListingCategory.books)),
      );
      await n.smartSearch('βιβλία');
      n.clearFilters();
      expect(n.state.aiApplied, isFalse);
      expect(n.state.category, isNull);
      expect(n.state.query, 'βιβλίο');
    });
  });

  group('semantic search', () {
    test('fromMap διαβάζει τα matches και αγνοεί χαλασμένα', () {
      final f = AiSearchFilters.fromMap({
        'keywords': ['καναπές'],
        'matches': [
          {'id': 'a', 'score': 0.71},
          {'id': 'b', 'score': 1},
          {'id': 3, 'score': 0.9},
          {'id': 'c'},
          'junk',
        ],
      });
      expect(f.matches, {'a': 0.71, 'b': 1.0});
    });

    test('φέρνει αγγελίες που βρήκε ΜΟΝΟ το νόημα, με τα ίδια φίλτρα', () async {
      final moving = _l('Βοήθεια σε μετακόμιση');
      final seekVan =
          _l('Ζητάω βαν', type: ListingType.seek); // λάθος τύπος → εκτός
      final repo = _FakeRepo([], byId: {
        moving.id: moving,
        seekVan.id: seekVan,
      });
      final n = SearchNotifier(
        repository: repo,
        ai: _FakeAi(
          filters: AiSearchFilters(
            keywords: const ['καναπές'],
            type: ListingType.offer,
            matches: {moving.id: 0.76, seekVan.id: 0.7},
          ),
        ),
      );

      await n.smartSearch('μεταφορά καναπέ');

      expect(repo.idCalls.single, containsAll([moving.id, seekVan.id]));
      expect(n.state.results.map((l) => l.id), [moving.id]);
    });

    test('δεν ξαναφέρνει όσα βρήκε ήδη η αναζήτηση λέξεων', () async {
      final tent = _l('Σκηνή κάμπινγκ');
      final repo = _FakeRepo([tent], byId: {tent.id: tent});
      final n = SearchNotifier(
        repository: repo,
        ai: _FakeAi(
            filters: AiSearchFilters(
                keywords: const ['σκηνή'], matches: {tent.id: 0.71})),
      );
      await n.smartSearch('πάμε για κατασκήνωση');
      expect(repo.idCalls, isEmpty);
      expect(n.state.results, hasLength(1));
    });

    test('κατάταξη: λέξεις + νόημα πρώτα, μετά μόνο νόημα', () async {
      final both = _l('Σκηνή 4 ατόμων');
      final onlyMeaning = _l('Υπνόσακος', createdAt: DateTime(2026, 9, 1));
      final onlyWord = _l('Σκηνή θεάτρου (σκηνικά)');
      final repo = _FakeRepo([onlyWord, both], byId: {
        onlyMeaning.id: onlyMeaning,
      });
      final n = SearchNotifier(
        repository: repo,
        ai: _FakeAi(
          filters: AiSearchFilters(
            keywords: const ['σκηνή'],
            matches: {both.id: 0.72, onlyMeaning.id: 0.68},
          ),
        ),
      );
      await n.smartSearch('σκηνή για κάμπινγκ');
      expect(n.state.results.map((l) => l.id),
          [both.id, onlyMeaning.id, onlyWord.id]);
    });

    test('αλλαγή κειμένου πετά τα σημασιολογικά αποτελέσματα', () async {
      final moving = _l('Βοήθεια σε μετακόμιση');
      final repo = _FakeRepo([], byId: {moving.id: moving});
      final n = SearchNotifier(
        repository: repo,
        ai: _FakeAi(
            filters: AiSearchFilters(
                keywords: const ['καναπές'], matches: {moving.id: 0.76})),
      );
      await n.smartSearch('μεταφορά καναπέ');
      expect(n.state.results, hasLength(1));

      await n.search('ψυγείο');
      expect(n.state.semanticScores, isEmpty);
      expect(n.state.results, isEmpty);
    });

    test('αλλαγή φίλτρου ΚΡΑΤΑ τα σημασιολογικά (ίδιο ερώτημα)', () async {
      final moving = _l('Βοήθεια σε μετακόμιση',
          category: ListingCategory.services);
      final repo = _FakeRepo([], byId: {moving.id: moving});
      final n = SearchNotifier(
        repository: repo,
        ai: _FakeAi(
            filters: AiSearchFilters(
                keywords: const ['καναπές'], matches: {moving.id: 0.76})),
      );
      await n.smartSearch('μεταφορά καναπέ');
      n.setCategory(ListingCategory.tools);
      await Future<void>.delayed(Duration.zero);
      expect(n.state.semanticScores, isNotEmpty);
      expect(n.state.results, isEmpty); // services ≠ tools

      n.setCategory(ListingCategory.services);
      await Future<void>.delayed(Duration.zero);
      expect(n.state.results, hasLength(1));
    });

    test('μόνο σημασιολογικά (χωρίς λέξεις/φίλτρα) μετράει ως κριτήριο',
        () async {
      final stroller = _l('Καρότσι μωρού');
      final repo = _FakeRepo([], byId: {stroller.id: stroller});
      final n = SearchNotifier(
        repository: repo,
        ai: _FakeAi(
            filters: AiSearchFilters(matches: {stroller.id: 0.70})),
      );
      await n.smartSearch('kati gia to moro');
      expect(n.state.hasCriteria, isTrue);
      expect(n.state.results, hasLength(1));
    });
  });
}
