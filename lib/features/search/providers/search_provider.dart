import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/location_permission_gate.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/listing_repository.dart';
import '../../../core/services/ai_functions.dart';
import '../data/search_ai_service.dart';
import '../presentation/widgets/search_filters_widget.dart';
export 'package:shareit/features/search/presentation/widgets/search_filters_widget.dart'
    show SearchSort;

class SearchState {
  final String query;
  final Set<String> tags;
  final ListingType? type;
  final ListingCategory? category;
  final DateTime? availableFrom;
  final DateTime? availableUntil;
  final SearchSort sort;
  final double distanceKm;
  final List<ListingModel> results;
  final bool loading;
  final String? error;

  /// Το AI αναλύει τη φράση (πριν ξεκινήσει η κανονική αναζήτηση).
  final bool aiLoading;

  /// Τα τρέχοντα φίλτρα προήλθαν από AI — η οθόνη το δείχνει, ώστε ο χρήστης
  /// να ξέρει γιατί άλλαξαν μόνα τους τα chips.
  final bool aiApplied;

  /// Μη-μοιραίο μήνυμα (π.χ. «AI μη διαθέσιμο, έγινε απλή αναζήτηση»).
  final String? notice;

  /// Σημασιολογικά αποτελέσματα του AI (id → ομοιότητα 0..1) για το ερώτημα
  /// [semanticQuery]. Ισχύουν ΜΟΝΟ όσο το ερώτημα μένει το ίδιο — αλλάζουν τα
  /// φίλτρα, όχι το νόημα· αλλάζει το κείμενο, πετιούνται.
  final Map<String, double> semanticScores;
  final String semanticQuery;

  const SearchState({
    this.query = '',
    this.tags = const {},
    this.type,
    this.category,
    this.availableFrom,
    this.availableUntil,
    this.sort = SearchSort.recent,
    this.distanceKm = 800,
    this.results = const [],
    this.loading = false,
    this.error,
    this.aiLoading = false,
    this.aiApplied = false,
    this.notice,
    this.semanticScores = const {},
    this.semanticQuery = '',
  });

  /// Υπάρχει ΟΤΙΔΗΠΟΤΕ προς αναζήτηση; Μόνο τότε τρέχει query — αλλιώς θα
  /// φέρναμε 60 τυχαίες αγγελίες. (Η απόσταση/ταξινόμηση μόνες τους δεν
  /// μετράνε: περιορίζουν, δεν περιγράφουν τι ψάχνεις.)
  bool get hasCriteria =>
      query.trim().isNotEmpty ||
      tags.isNotEmpty ||
      category != null ||
      availableFrom != null ||
      availableUntil != null ||
      semanticScores.isNotEmpty;

  bool get hasDateFilter => availableFrom != null || availableUntil != null;

  SearchState copyWith({
    String? query,
    Set<String>? tags,
    ListingType? type,
    ListingCategory? category,
    DateTime? availableFrom,
    DateTime? availableUntil,
    SearchSort? sort,
    double? distanceKm,
    List<ListingModel>? results,
    bool? loading,
    String? error,
    bool? aiLoading,
    bool? aiApplied,
    String? notice,
    Map<String, double>? semanticScores,
    String? semanticQuery,
    bool clearType = false,
    bool clearCategory = false,
    bool clearDates = false,
    bool clearNotice = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        tags: tags ?? this.tags,
        type: clearType ? null : (type ?? this.type),
        category: clearCategory ? null : (category ?? this.category),
        availableFrom:
            clearDates ? null : (availableFrom ?? this.availableFrom),
        availableUntil:
            clearDates ? null : (availableUntil ?? this.availableUntil),
        sort: sort ?? this.sort,
        distanceKm: distanceKm ?? this.distanceKm,
        results: results ?? this.results,
        loading: loading ?? this.loading,
        error: error,
        aiLoading: aiLoading ?? this.aiLoading,
        aiApplied: aiApplied ?? this.aiApplied,
        // Σε αντίθεση με το error, το notice ΕΠΙΒΙΩΝΕΙ των επόμενων
        // copyWith: το smartSearch το θέτει και αμέσως μετά τρέχει search().
        notice: clearNotice ? null : (notice ?? this.notice),
        semanticScores: semanticScores ?? this.semanticScores,
        semanticQuery: semanticQuery ?? this.semanticQuery,
      );
}

class SearchNotifier extends StateNotifier<SearchState> {
  /// Εξαρτήσεις με injection: στην παραγωγή οι πραγματικές, στα tests fakes
  /// (χωρίς Firebase/GPS/δίκτυο).
  SearchNotifier({
    ListingRepository? repository,
    SearchAiService? ai,
    Future<Position?> Function()? locate,
  })  : _repoOverride = repository,
        _aiOverride = ai,
        _locate = locate,
        super(const SearchState());

  final ListingRepository? _repoOverride;
  final SearchAiService? _aiOverride;
  final Future<Position?> Function()? _locate;

  ListingRepository get _repo => _repoOverride ?? ListingRepository();
  SearchAiService get _ai => _aiOverride ?? SearchAiService();

  /// Αυξάνεται σε κάθε νέα αναζήτηση. Αν μια παλιά (αργή) απάντηση φτάσει
  /// μετά από νεότερη, την αγνοούμε — αλλιώς θα έγραφε από πάνω πιο φρέσκα
  /// αποτελέσματα (κλασικό race στο search-as-you-type).
  int _generation = 0;

  /// Βάρος της σημασιολογικής ομοιότητας στην κατάταξη: ομοιότητα 0.7 → 7
  /// πόντοι ≈ δύο λέξεις στον τίτλο. Μια αγγελία που ταιριάζει ΚΑΙ σε λέξεις
  /// ΚΑΙ σε νόημα ανεβαίνει πρώτη.
  static const double _semanticWeight = 10;

  Future<void> search(String query) async {
    final gen = ++_generation;
    state = state.copyWith(query: query);
    if (state.semanticScores.isNotEmpty && query != state.semanticQuery) {
      state = state.copyWith(semanticScores: const {}, semanticQuery: '');
    }
    if (!state.hasCriteria) {
      state = state.copyWith(results: [], loading: false, query: '');
      return;
    }
    state = state.copyWith(loading: true, error: null);
    try {
      // Αντίγραφο (modifiable): το sort() παρακάτω δεν πρέπει να τροποποιεί τη
      // λίστα που επιστρέφει το repository (μπορεί να είναι read-only).
      var results = List<ListingModel>.of(await _repo.search(
        keyword: query,
        tags: state.tags,
        type: state.type,
        category: state.category,
        availableFrom: state.availableFrom,
        availableUntil: state.availableUntil,
      ));

      // Σημασιολογικά αποτελέσματα που ΔΕΝ βρήκε η αναζήτηση λέξεων: έρχονται
      // ως ids χωρίς φίλτρα, οπότε περνούν από τα ΙΔΙΑ φίλτρα του client.
      final semantic = state.semanticScores;
      if (semantic.isNotEmpty) {
        final have = results.map((l) => l.id).toSet();
        final missing = semantic.keys.where((id) => !have.contains(id));
        if (missing.isNotEmpty) {
          try {
            results.addAll(ListingRepository.applyFilters(
              await _repo.getActiveByIds(missing),
              tags: state.tags,
              type: state.type,
              category: state.category,
              availableFrom: state.availableFrom,
              availableUntil: state.availableUntil,
            ));
          } catch (_) {
            // Μπόνους, όχι προϋπόθεση: μένουν τα αποτελέσματα λέξεων.
          }
        }
      }

      // Φέρε τη θέση ΜΙΑ φορά αν τη χρειάζεται είτε το φίλτρο απόστασης είτε
      // η ταξινόμηση "κοντινά" — αποφεύγουμε διπλό (αργό) GPS fix.
      final needsPosition =
          state.distanceKm < 800 || state.sort == SearchSort.nearest;
      final pos =
          needsPosition ? await (_locate ?? _getUserPosition)() : null;

      if (state.distanceKm < 800 && pos != null) {
        results = results.where((l) {
          final dist = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            l.location.latitude,
            l.location.longitude,
          );
          return dist <= (state.distanceKm * 1000);
        }).toList();
      }

      if (state.sort == SearchSort.nearest) {
        if (pos != null) {
          results.sort((a, b) {
            final da = Geolocator.distanceBetween(pos.latitude, pos.longitude,
                a.location.latitude, a.location.longitude);
            final db = Geolocator.distanceBetween(pos.latitude, pos.longitude,
                b.location.latitude, b.location.longitude);
            return da.compareTo(db);
          });
        }
      } else {
        // Προεπιλογή: ΣΧΕΤΙΚΟΤΗΤΑ. Όσο περισσότερες λέξεις του ερωτήματος
        // περιέχει η αγγελία, τόσο πιο ψηλά· σε ισοβαθμία, η νεότερη πρώτη.
        // Χωρίς όρους (π.χ. μόνο φίλτρο tag) κρατάμε την παλιά ταξινόμηση
        // κατά ημερομηνία, ώστε να μην αλλάξει η υπάρχουσα συμπεριφορά.
        final tokens = ListingRepository.queryTokens(query);
        if (tokens.isEmpty && semantic.isEmpty) {
          results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        } else {
          double score(ListingModel l) =>
              ListingRepository.relevance(l, tokens) +
              (semantic[l.id] ?? 0) * _semanticWeight;
          results.sort((a, b) {
            final byScore = score(b).compareTo(score(a));
            return byScore != 0 ? byScore : b.createdAt.compareTo(a.createdAt);
          });
        }
      }

      if (gen != _generation) return;
      state = state.copyWith(results: results, loading: false);
    } catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(
          loading: false, error: 'srch.searchError'.tr());
    }
  }

  /// Αναζήτηση σε ΦΥΣΙΚΗ ΓΛΩΣΣΑ: «ψάχνω παιδικό ποδήλατο κοντά μου το Σάββατο».
  ///
  /// Το AI ΔΕΝ ψάχνει το ίδιο — μετατρέπει τη φράση σε φίλτρα (τύπος,
  /// κατηγορία, απόσταση, ημερομηνίες, λέξεις+συνώνυμα) και μετά τρέχει η
  /// ΙΔΙΑ [search] με αυτά. Έτσι τα φίλτρα φαίνονται ως chips και ο χρήστης τα
  /// διορθώνει, και η αναζήτηση μένει ντετερμινιστική/φθηνή.
  ///
  /// Αν το AI αποτύχει (δίκτυο, όριο χρήσης), πέφτουμε σιωπηλά σε απλή
  /// αναζήτηση λέξεων — η εφαρμογή δεν «σπάει» ποτέ λόγω AI.
  Future<void> smartSearch(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;
    final gen = ++_generation;
    state = state.copyWith(aiLoading: true, error: null);

    AiSearchFilters f;
    try {
      f = await _ai.parse(query);
    } on AiException catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(
        aiLoading: false,
        aiApplied: false,
        notice: e.reason == AiFailure.quota
            ? 'srch.aiQuota'.tr()
            : 'srch.aiUnavailable'.tr(),
      );
      await search(query);
      return;
    }
    if (gen != _generation) return;

    // Τα φίλτρα του AI ΑΝΤΙΚΑΘΙΣΤΟΥΝ τα προηγούμενα: νέα ερώτηση, νέο
    // πλαίσιο. Τα tags (επιλογή με το χέρι) καθαρίζουν για τον ίδιο λόγο.
    state = SearchState(
      type: f.type,
      category: f.category,
      availableFrom: f.availableFrom,
      availableUntil: f.availableUntil,
      sort: f.sortNearest ? SearchSort.nearest : SearchSort.recent,
      distanceKm: f.maxDistanceKm ?? 800,
      aiApplied: true,
      semanticScores: f.matches,
      semanticQuery: f.keywords.join(' '),
    );
    await search(f.keywords.join(' '));
  }

  Future<Position?> _getUserPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final perm = await LocationPermissionGate.ensure();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      // ΓΡΗΓΟΡΟ: πρώτα η τελευταία γνωστή θέση (ακαριαία). Μόνο αν λείπει,
      // ζητάμε νέο fix με medium accuracy + timeout, ώστε να μη «κολλάει» η
      // αναζήτηση περιμένοντας high-accuracy GPS.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Toggle a tag in/out of the active filter set. Tapping a selected tag
  /// removes it; multiple tags can be active at once.
  void toggleTag(String tag) {
    final next = Set<String>.from(state.tags);
    if (!next.add(tag)) next.remove(tag); // add() is false if already present
    state = state.copyWith(tags: next);
    search(state.query);
  }

  void clearTags() {
    state = state.copyWith(tags: const {});
    search(state.query);
  }

  void setType(ListingType? t) {
    state = state.copyWith(type: t, clearType: t == null);
    if (state.hasCriteria) search(state.query);
  }

  /// Η κατηγορία είναι ΑΠΟ ΜΟΝΗ ΤΗΣ κριτήριο: «δείξε μου όλα τα εργαλεία».
  void setCategory(ListingCategory? c) {
    state = state.copyWith(category: c, clearCategory: c == null);
    search(state.query);
  }

  /// Διαθέσιμο κάποια στιγμή μέσα στο [from, until]· null/null = καθαρισμός.
  void setAvailability(DateTime? from, DateTime? until) {
    state = state.copyWith(
      availableFrom: from,
      availableUntil: until,
      clearDates: from == null && until == null,
    );
    search(state.query);
  }

  void setSort(SearchSort s) {
    state = state.copyWith(sort: s);
    if (state.hasCriteria) search(state.query);
  }

  void setDistance(double km) {
    state = state.copyWith(distanceKm: km);
    if (state.hasCriteria) search(state.query);
  }

  /// Καθαρίζει ΟΛΑ τα φίλτρα (και του AI) κρατώντας το κείμενο.
  void clearFilters() {
    final q = state.query;
    state = const SearchState();
    if (q.isNotEmpty) search(q);
  }

  void clear() {
    _generation++; // ακύρωσε ό,τι εκκρεμεί
    state = const SearchState();
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>(
    (ref) => SearchNotifier());
