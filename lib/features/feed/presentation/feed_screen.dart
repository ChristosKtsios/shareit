import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/listing_card.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/tags_repository.dart';
import '../../search/presentation/widgets/search_filters_widget.dart';
import '../providers/feed_provider.dart';
import 'widgets/feed_filters_sheet.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scrollCtrl = ScrollController();
  List<String> _trendingTags = [];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadTrendingTags();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent * 0.8) {
      ref.read(feedProvider.notifier).loadNextPage();
    }
  }

  Future<void> _loadTrendingTags() async {
    try {
      final tags = await TagsRepository().getTrendingTags(limit: 15);
      if (mounted) {
        setState(() => _trendingTags = tags.map((t) => t.name).toList());
      }
    } catch (_) {}
  }

  void _openFiltersSheet() {
    final state = ref.read(feedProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FeedFiltersSheet(
        initialDistance: state.distance,
        initialSort: state.sort,
        initialTagFilter: state.tagFilter,
        trendingTags: _trendingTags,
        onApply: (distance, sort, tag) {
          final notifier = ref.read(feedProvider.notifier);
          notifier.setDistance(distance);
          notifier.setSort(sort);
          notifier.setTagFilter(tag);
        },
      ),
    );
  }

  /// Μετράει πόσα φίλτρα είναι ενεργά (εκτός default)
  int _activeFiltersCount(FeedState state) {
    var count = 0;
    if (state.distance != SearchDistance.all) count++;
    if (state.sort != SearchSort.recent) count++;
    if (state.tagFilter != null) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(feedProvider);
    final notifier = ref.read(feedProvider.notifier);
    final listings = state.filtered;
    final activeCount = _activeFiltersCount(state);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.navFeed),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: Column(children: [
        // Type filters (Όλα / Προσφέρω / Αναζητώ)
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              _Chip(
                  label: 'Όλα',
                  selected: state.type == null,
                  onTap: () => notifier.setType(null)),
              const SizedBox(width: 6),
              _Chip(
                  label: '🤲 Προσφέρω',
                  selected: state.type == ListingType.offer,
                  color: AppColors.offer,
                  onTap: () => notifier.setType(state.type == ListingType.offer
                      ? null
                      : ListingType.offer)),
              const SizedBox(width: 6),
              _Chip(
                  label: '🔍 Αναζητώ',
                  selected: state.type == ListingType.seek,
                  color: AppColors.seek,
                  onTap: () => notifier.setType(state.type == ListingType.seek
                      ? null
                      : ListingType.seek)),
            ],
          ),
        ),

        // Filters button + active filters chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Filters button με badge
              GestureDetector(
                onTap: _openFiltersSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: activeCount > 0
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: activeCount > 0
                            ? AppColors.primary
                            : AppColors.border,
                        width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune,
                          color: activeCount > 0
                              ? Colors.white
                              : AppColors.textPrimary,
                          size: 16),
                      const SizedBox(width: 6),
                      Text(AppStrings.filters,
                          style: TextStyle(
                              color: activeCount > 0
                                  ? Colors.white
                                  : AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      if (activeCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$activeCount',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Active filter pills
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (state.distance != SearchDistance.all)
                        _ActivePill(
                          label: state.distance.label,
                          onRemove: () =>
                              notifier.setDistance(SearchDistance.all),
                        ),
                      if (state.sort != SearchSort.recent)
                        _ActivePill(
                          label: '📍 Κοντινά',
                          onRemove: () => notifier.setSort(SearchSort.recent),
                        ),
                      if (state.tagFilter != null)
                        _ActivePill(
                          label: '#${state.tagFilter}',
                          onRemove: () => notifier.setTagFilter(null),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 0),

        // Counter
        if (listings.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surfaceVariant,
            child: Row(children: [
              Text('${listings.length} αγγελίες',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const Spacer(),
              Text(
                  state.sort == SearchSort.recent
                      ? '🕐 Πιο πρόσφατα'
                      : '📍 Πιο κοντινά',
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 11)),
            ]),
          ),

        // Λίστα αγγελιών
        Expanded(
          child: state.listings.isEmpty && state.isLoading
              ? const ShimmerList(count: 5)
              : listings.isEmpty
                  ? const Center(
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off,
                            color: AppColors.textHint, size: 48),
                        SizedBox(height: 12),
                        Text('Δεν υπάρχουν αγγελίες\nγια αυτό το φίλτρο.',
                            style: TextStyle(color: AppColors.textSecondary),
                            textAlign: TextAlign.center),
                      ],
                    ))
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: () => notifier.refresh(),
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: listings.length +
                            (state.isLoading ? 1 : 0) +
                            (!state.hasMore && listings.isNotEmpty ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == listings.length && state.isLoading) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 2)),
                            );
                          }
                          if (i == listings.length && !state.hasMore) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  'Δεν υπάρχουν άλλες αγγελίες',
                                  style: TextStyle(
                                      color: AppColors.textHint, fontSize: 12),
                                ),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ListingCard(
                              listing: listings[i],
                              onTap: () =>
                                  context.push('/listing/${listings[i].id}'),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color:
              selected ? c.withValues(alpha: 0.15) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? c : AppColors.border,
              width: selected ? 1.5 : 0.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? c : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActivePill({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: AppColors.primary, size: 14),
          ),
        ],
      ),
    );
  }
}
