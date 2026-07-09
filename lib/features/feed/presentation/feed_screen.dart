import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/listing_card.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../listings/data/listing_model.dart';
import '../../search/presentation/widgets/distance_slider_widget.dart';
import '../providers/feed_provider.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(feedProvider);
    final notifier = ref.read(feedProvider.notifier);
    final listings = state.filtered;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          const Text('Share',
              style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: -0.5)),
          const Text('It',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: -0.5)),
          const SizedBox(width: 6),
          Text('€',
              style: TextStyle(
                  color: AppColors.deal.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(width: 2),
          Text('\$',
              style: TextStyle(
                  color: AppColors.deal.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ]),
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
                  label: 'filters.all'.tr(),
                  selected: state.type == null,
                  onTap: () => notifier.setType(null)),
              const SizedBox(width: 6),
              _Chip(
                  label: 'filters.offer'.tr(),
                  selected: state.type == ListingType.offer,
                  color: AppColors.offer,
                  onTap: () => notifier.setType(state.type == ListingType.offer
                      ? null
                      : ListingType.offer)),
              const SizedBox(width: 6),
              _Chip(
                  label: 'filters.seek'.tr(),
                  selected: state.type == ListingType.seek,
                  color: AppColors.seek,
                  onTap: () => notifier.setType(state.type == ListingType.seek
                      ? null
                      : ListingType.seek)),
            ],
          ),
        ),

        // Distance slider — απόσταση 1–100 χλμ (με persistence)
        DistanceSliderWidget(
          value: state.distanceKm,
          onChanged: notifier.setDistance,
        ),

        const Divider(height: 0),

        // Counter
        if (listings.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surfaceVariant,
            child: Row(children: [
              Text('feed.countListings'.tr(namedArgs: {'n': '${listings.length}'}),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ]),
          ),

        // Λίστα αγγελιών
        Expanded(
          child: state.listings.isEmpty && state.isLoading
              ? const ShimmerList(count: 5)
              : listings.isEmpty
                  ? Center(
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off,
                            color: AppColors.textHint, size: 48),
                        const SizedBox(height: 12),
                        Text('feed.emptyFilter'.tr(),
                            style: const TextStyle(
                                color: AppColors.textSecondary),
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
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  'feed.noMore'.tr(),
                                  style: const TextStyle(
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

