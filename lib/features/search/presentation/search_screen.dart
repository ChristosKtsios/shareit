import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/providers/blocked_users_provider.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/tags_repository.dart';
import '../../listings/presentation/widgets/category_selector.dart'
    show ListingCategoryX;
import '../providers/search_provider.dart';
import 'widgets/search_bar_widget.dart';
import 'widgets/search_results_widget.dart';

enum SearchMode { listings, users }

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  List<String> _trendingTags = [];
  SearchMode _mode = SearchMode.listings;
  List<Map<String, dynamic>> _userResults = [];
  bool _userLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadTrendingTags();
  }

  Future<void> _loadTrendingTags() async {
    try {
      final tags = await TagsRepository().getTrendingTags(limit: 12);
      if (mounted) {
        setState(() => _trendingTags = tags.map((t) => t.name).toList());
      }
    } catch (_) {}
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _userResults = []);
      return;
    }
    setState(() => _userLoading = true);
    try {
      final q = query.toLowerCase().trim();
      final snap =
          await FirebaseFirestore.instance.collection('users').limit(50).get();
      final matches = snap.docs.where((doc) {
        final data = doc.data();
        final first = (data['firstName'] as String? ?? '').toLowerCase();
        final last = (data['lastName'] as String? ?? '').toLowerCase();
        final full = '$first $last'.trim();
        return first.contains(q) || last.contains(q) || full.contains(q);
      }).map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        return data;
      }).toList();
      if (mounted) {
        setState(() {
          _userResults = matches;
          _userLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _userLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String _formatDistance(double km) {
    if (km >= 800) return 'dist.everywhere'.tr();
    if (km < 1) {
      return 'dist.meters'.tr(namedArgs: {'n': '${(km * 1000).toInt()}'});
    }
    return 'dist.kmValue'.tr(namedArgs: {'n': '${km.toInt()}'});
  }

  Widget _buildToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _mode = SearchMode.listings),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _mode == SearchMode.listings
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surfaceVariant,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
                border: Border.all(
                  color: _mode == SearchMode.listings
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
              child: Center(
                child: Text('srch.tabListings'.tr(),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _mode = SearchMode.users),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _mode == SearchMode.users
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surfaceVariant,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                border: Border.all(
                  color: _mode == SearchMode.users
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
              child: Center(
                child: Text('srch.tabUsers'.tr(),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildTypeChips(SearchState state, SearchNotifier notifier) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _Chip(
              label: 'filters.all'.tr(),
              selected: state.type == null,
              onTap: () => notifier.setType(null)),
          const SizedBox(width: 6),
          _Chip(
              label: 'filters.offer'.tr(),
              selected: state.type == ListingType.offer,
              color: AppColors.offer,
              onTap: () => notifier.setType(
                  state.type == ListingType.offer ? null : ListingType.offer)),
          const SizedBox(width: 6),
          _Chip(
              label: 'filters.seek'.tr(),
              selected: state.type == ListingType.seek,
              color: AppColors.seek,
              onTap: () => notifier.setType(
                  state.type == ListingType.seek ? null : ListingType.seek)),
          const SizedBox(width: 12),
          _Chip(
            label: state.hasDateFilter
                ? '📅 ${_formatDateRange(state)}'
                : 'filters.anyDate'.tr(),
            selected: state.hasDateFilter,
            color: AppColors.deal,
            onTap: () => _pickDates(state, notifier),
          ),
        ],
      ),
    );
  }

  String _formatDateRange(SearchState state) {
    final f = DateFormat('d/M', context.locale.toString());
    final from = state.availableFrom;
    final until = state.availableUntil;
    if (from != null && until != null) {
      return from == until ? f.format(from) : '${f.format(from)}–${f.format(until)}';
    }
    return f.format((from ?? until)!);
  }

  /// Ενεργό φίλτρο → το πάτημα το ΚΑΘΑΡΙΖΕΙ (όπως τα υπόλοιπα chips).
  /// Ανενεργό → ανοίγει επιλογή διαστήματος.
  Future<void> _pickDates(SearchState state, SearchNotifier notifier) async {
    if (state.hasDateFilter) {
      notifier.setAvailability(null, null);
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'filters.availableWhen'.tr(),
    );
    if (range != null) notifier.setAvailability(range.start, range.end);
  }

  Widget _buildCategoryChips(SearchState state, SearchNotifier notifier) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _Chip(
              label: 'filters.categoryAll'.tr(),
              selected: state.category == null,
              onTap: () => notifier.setCategory(null)),
          const SizedBox(width: 6),
          ...ListingCategory.values.map((c) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _Chip(
                  label: c.label,
                  icon: c.icon,
                  selected: state.category == c,
                  onTap: () =>
                      notifier.setCategory(state.category == c ? null : c),
                ),
              )),
        ],
      ),
    );
  }

  /// «✨ Φίλτρα από AI» ή μήνυμα fallback. Διαφάνεια: ο χρήστης πρέπει να
  /// ξέρει ΓΙΑΤΙ άλλαξαν τα chips μόνα τους — και να μπορεί να τα αναιρέσει.
  Widget _buildAiBanner(SearchState state, SearchNotifier notifier) {
    final String text;
    final IconData icon;
    if (state.aiLoading) {
      text = 'srch.aiThinking'.tr();
      icon = Icons.auto_awesome;
    } else if (state.notice != null) {
      text = state.notice!;
      icon = Icons.info_outline;
    } else if (state.aiApplied) {
      text = 'srch.aiApplied'.tr();
      icon = Icons.auto_awesome;
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
        if (state.aiApplied && !state.aiLoading)
          TextButton(
            onPressed: notifier.clearFilters,
            child: Text('filters.clearAll'.tr(),
                style: const TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _buildDistanceSlider(SearchState state, SearchNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Row(children: [
        const Icon(Icons.my_location, color: AppColors.primary, size: 16),
        const SizedBox(width: 6),
        Text('dist.label'.tr(),
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.surfaceVariant,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              min: 1,
              max: 800,
              divisions: 80,
              value: state.distanceKm.clamp(1, 800),
              onChanged: (v) => notifier.setDistance(v),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _formatDistance(state.distanceKm),
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _buildTagsRow(SearchState state, SearchNotifier notifier) {
    if (_trendingTags.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _Chip(
              label: 'filters.tagAll'.tr(),
              selected: state.tags.isEmpty,
              onTap: () => notifier.clearTags()),
          const SizedBox(width: 6),
          ..._trendingTags.map((tag) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _Chip(
                  label: '#$tag',
                  selected: state.tags.contains(tag),
                  showCheck: true,
                  onTap: () => notifier.toggleTag(tag),
                ),
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawState = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    // Οι αγγελίες μπλοκαρισμένων χρηστών δεν εμφανίζονται στα αποτελέσματα.
    final blocked = ref.blockedUids;
    final state = blocked.isEmpty
        ? rawState
        : rawState.copyWith(
            results: rawState.results
                .where((l) => !blocked.contains(l.userId))
                .toList());
    // Το ίδιο και στην αναζήτηση χρηστών: ο μπλοκαρισμένος δεν εμφανίζεται.
    final userResults = blocked.isEmpty
        ? _userResults
        : _userResults
            .where((u) => !blocked.contains(u['uid'] as String?))
            .toList();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(AppStrings.search),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/map');
            }
          },
        ),
      ),
      body: Column(children: [
        SearchBarWidget(
          controller: _ctrl,
          onChanged: (v) {
            // Debounce: εκτελεί την αναζήτηση 350ms αφού σταματήσει η
            // πληκτρολόγηση, ώστε να μη γίνεται query σε κάθε πλήκτρο.
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              if (!mounted) return;
              if (_mode == SearchMode.listings) {
                notifier.search(v);
              } else {
                _searchUsers(v);
              }
            });
          },
          onClear: () {
            _debounce?.cancel();
            _ctrl.clear();
            notifier.clear();
            setState(() => _userResults = []);
          },
          aiLoading: state.aiLoading,
          onAiSearch: _mode == SearchMode.listings
              ? (v) {
                  // Η AI αναζήτηση αντικαθιστά την εκκρεμή απλή αναζήτηση.
                  _debounce?.cancel();
                  FocusScope.of(context).unfocus();
                  notifier.smartSearch(v);
                }
              : null,
        ),
        const Divider(height: 0),
        _buildToggle(),
        if (_mode == SearchMode.listings) ...[
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildAiBanner(state, notifier)),
                SliverToBoxAdapter(child: _buildTypeChips(state, notifier)),
                SliverToBoxAdapter(
                    child: _buildCategoryChips(state, notifier)),
                SliverToBoxAdapter(
                    child: _buildDistanceSlider(state, notifier)),
                SliverToBoxAdapter(child: _buildTagsRow(state, notifier)),
                const SliverToBoxAdapter(child: Divider(height: 0)),
                if (state.results.isNotEmpty && !state.loading)
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      color: AppColors.surfaceVariant,
                      child: Row(children: [
                        Text(
                            'srch.countResults'.tr(
                                namedArgs: {'n': '${state.results.length}'}),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                      ]),
                    ),
                  ),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: SearchResultsWidget(
                    state: state,
                    notifier: notifier,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Expanded(
            child: _userLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : userResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_search,
                                color: AppColors.textHint, size: 48),
                            const SizedBox(height: 12),
                            Text('srch.searchUserHint'.tr(),
                                style: const TextStyle(
                                    color: AppColors.textHint)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: userResults.length,
                        itemBuilder: (_, i) {
                          final u = userResults[i];
                          final first = u['firstName'] as String? ?? '';
                          final last = u['lastName'] as String? ?? '';
                          final fullName = '$first $last'.trim();
                          final avatarUrl = u['avatarUrl'] as String?;
                          final rating =
                              (u['rating'] as num?)?.toDouble() ?? 0.0;
                          final ratingCount =
                              (u['ratingCount'] as num?)?.toInt() ?? 0;
                          // Badge = γνήσιο OTP (phoneVerified), όχι το
                          // always-true isVerified.
                          final isVerified =
                              u['phoneVerified'] as bool? ?? false;
                          String initials = '?';
                          if (first.isNotEmpty && last.isNotEmpty) {
                            initials = '${first[0]}${last[0]}'.toUpperCase();
                          } else if (first.isNotEmpty) {
                            initials = first[0].toUpperCase();
                          }
                          return ListTile(
                            leading: UserAvatar(
                                initials: initials,
                                avatarUrl: avatarUrl,
                                radius: 22,
                                showVerified: isVerified),
                            title: Text(
                              fullName.isEmpty ? 'common.userFallback'.tr() : fullName,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Row(children: [
                              const Icon(Icons.star,
                                  color: AppColors.deal, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                  '${rating.toStringAsFixed(1)} ($ratingCount)',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                            ]),
                            trailing: const Icon(Icons.chevron_right,
                                color: AppColors.textHint),
                            onTap: () => context.push('/profile/${u['uid']}'),
                          );
                        },
                      ),
          ),
        ],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  /// Δείχνει ✓ όταν είναι επιλεγμένο — για tags που υποστηρίζουν πολλαπλή
  /// επιλογή, ώστε να είναι ξεκάθαρο ποια είναι ενεργά (και ότι re-tap αφαιρεί).
  final bool showCheck;
  final IconData? icon;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.showCheck = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color:
              selected ? c.withValues(alpha: 0.15) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? c : AppColors.border,
              width: selected ? 1.5 : 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (showCheck && selected) ...[
            Icon(Icons.check, size: 14, color: c),
            const SizedBox(width: 4),
          ] else if (icon != null) ...[
            Icon(icon,
                size: 14,
                color: selected ? c : AppColors.textSecondary),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: selected ? c : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }
}
