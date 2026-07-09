import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../listings/data/listing_model.dart';

enum SearchSort { recent, nearest }

enum SearchDistance { km1, km5, km10, km50, all, custom }

extension SearchDistanceX on SearchDistance {
  static double _customKm = 25; // default custom value

  String get label {
    switch (this) {
      case SearchDistance.km1:
        return 'dist.km1'.tr();
      case SearchDistance.km5:
        return 'dist.km5'.tr();
      case SearchDistance.km10:
        return 'dist.km10'.tr();
      case SearchDistance.km50:
        return 'dist.km50'.tr();
      case SearchDistance.all:
        return 'dist.everywhere'.tr();
      case SearchDistance.custom:
        return 'dist.kmValueShort'.tr(namedArgs: {'n': '${_customKm.toInt()}'});
    }
  }

  double? get km {
    switch (this) {
      case SearchDistance.km1:
        return 1;
      case SearchDistance.km5:
        return 5;
      case SearchDistance.km10:
        return 10;
      case SearchDistance.km50:
        return 50;
      case SearchDistance.all:
        return null;
      case SearchDistance.custom:
        return _customKm;
    }
  }

  bool get isCustom => this == SearchDistance.custom;

  /// Δημιουργεί custom distance με δεδομένα km
  static SearchDistance fromCustomKm(double km) {
    _customKm = km;
    return SearchDistance.custom;
  }
}

// Το υπόλοιπο SearchFiltersWidget παραμένει το ίδιο
class SearchFiltersWidget extends StatelessWidget {
  final ListingType? activeType;
  final String? activeTag;
  final SearchSort activeSort;
  final SearchDistance activeDistance;
  final List<String> trendingTags;
  final void Function(ListingType?) onTypeChanged;
  final void Function(String?) onTagChanged;
  final void Function(SearchSort) onSortChanged;
  final void Function(SearchDistance) onDistanceChanged;

  const SearchFiltersWidget({
    super.key,
    required this.activeType,
    required this.activeTag,
    required this.activeSort,
    required this.activeDistance,
    required this.trendingTags,
    required this.onTypeChanged,
    required this.onTagChanged,
    required this.onSortChanged,
    required this.onDistanceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            _Chip(
                label: 'filters.all'.tr(),
                selected: activeType == null,
                onTap: () => onTypeChanged(null)),
            const SizedBox(width: 6),
            _Chip(
                label: 'filters.offer'.tr(),
                selected: activeType == ListingType.offer,
                color: AppColors.offer,
                onTap: () => onTypeChanged(activeType == ListingType.offer
                    ? null
                    : ListingType.offer)),
            const SizedBox(width: 6),
            _Chip(
                label: 'filters.seek'.tr(),
                selected: activeType == ListingType.seek,
                color: AppColors.seek,
                onTap: () => onTypeChanged(
                    activeType == ListingType.seek ? null : ListingType.seek)),
            const SizedBox(width: 12),
            _Chip(
              label: activeSort == SearchSort.recent
                  ? 'filters.sortRecentShort'.tr()
                  : 'filters.sortNearestShort'.tr(),
              selected: true,
              color: AppColors.deal,
              onTap: () => onSortChanged(activeSort == SearchSort.recent
                  ? SearchSort.nearest
                  : SearchSort.recent),
            ),
          ],
        ),
      ),
      if (trendingTags.isNotEmpty)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _Chip(
                  label: 'filters.tagAll'.tr(),
                  selected: activeTag == null,
                  onTap: () => onTagChanged(null)),
              const SizedBox(width: 6),
              ...trendingTags.map((tag) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Chip(
                      label: '#$tag',
                      selected: activeTag == tag,
                      onTap: () => onTagChanged(activeTag == tag ? null : tag),
                    ),
                  )),
            ],
          ),
        ),
      const Divider(height: 0),
    ]);
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
