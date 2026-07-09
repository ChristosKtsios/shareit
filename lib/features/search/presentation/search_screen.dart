import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/tags_repository.dart';
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
        ],
      ),
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
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);

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
            _ctrl.clear();
            notifier.clear();
            setState(() => _userResults = []);
          },
        ),
        const Divider(height: 0),
        _buildToggle(),
        if (_mode == SearchMode.listings) ...[
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildTypeChips(state, notifier)),
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
                : _userResults.isEmpty
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
                        itemCount: _userResults.length,
                        itemBuilder: (_, i) {
                          final u = _userResults[i];
                          final first = u['firstName'] as String? ?? '';
                          final last = u['lastName'] as String? ?? '';
                          final fullName = '$first $last'.trim();
                          final avatarUrl = u['avatarUrl'] as String?;
                          final rating =
                              (u['rating'] as num?)?.toDouble() ?? 0.0;
                          final ratingCount =
                              (u['ratingCount'] as num?)?.toInt() ?? 0;
                          final isVerified = u['isVerified'] as bool? ?? false;
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
                              fullName.isEmpty ? 'Χρήστης' : fullName,
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

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.showCheck = false,
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
