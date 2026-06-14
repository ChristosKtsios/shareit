import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/tags_repository.dart';
import '../providers/search_provider.dart';
import 'widgets/search_bar_widget.dart';
import 'widgets/search_results_widget.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  List<String> _trendingTags = [];

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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.search)),
      body: Column(children: [
        SearchBarWidget(
          controller: _ctrl,
          onChanged: (v) => notifier.search(v),
          onClear: () {
            _ctrl.clear();
            notifier.clear();
          },
        ),
        const Divider(height: 0),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              const SizedBox(width: 12),
              _Chip(
                label: state.sort == SearchSort.recent
                    ? '🕐 Πρόσφατα'
                    : '📍 Κοντινά',
                selected: true,
                color: AppColors.deal,
                onTap: () => notifier.setSort(state.sort == SearchSort.recent
                    ? SearchSort.nearest
                    : SearchSort.recent),
              ),
            ],
          ),
        ),
        if (_trendingTags.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _Chip(
                    label: '🏷️ Όλα',
                    selected: state.tagFilter == null,
                    onTap: () => notifier.setTagFilter(null)),
                const SizedBox(width: 6),
                ..._trendingTags.map((tag) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _Chip(
                        label: '#$tag',
                        selected: state.tagFilter == tag,
                        onTap: () => notifier
                            .setTagFilter(state.tagFilter == tag ? null : tag),
                      ),
                    )),
              ],
            ),
          ),
        const Divider(height: 0),
        if (state.results.isNotEmpty && !state.loading)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surfaceVariant,
            child: Row(children: [
              Text('${state.results.length} αποτελέσματα',
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
        Expanded(
            child: SearchResultsWidget(
          state: state,
          notifier: notifier,
        )),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}
