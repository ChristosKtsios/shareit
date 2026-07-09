import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../search/presentation/widgets/search_filters_widget.dart';

class FeedFiltersSheet extends StatefulWidget {
  final SearchDistance initialDistance;
  final SearchSort initialSort;
  final String? initialTagFilter;
  final List<String> trendingTags;
  final void Function(SearchDistance, SearchSort, String?) onApply;

  const FeedFiltersSheet({
    super.key,
    required this.initialDistance,
    required this.initialSort,
    required this.initialTagFilter,
    required this.trendingTags,
    required this.onApply,
  });

  @override
  State<FeedFiltersSheet> createState() => _FeedFiltersSheetState();
}

class _FeedFiltersSheetState extends State<FeedFiltersSheet> {
  late SearchDistance _distance;
  late SearchSort _sort;
  String? _tagFilter;
  final _kmCtrl = TextEditingController();
  bool _useCustomKm = false;

  @override
  void initState() {
    super.initState();
    _distance = widget.initialDistance;
    _sort = widget.initialSort;
    _tagFilter = widget.initialTagFilter;

    // Αν το initial distance είναι custom (δεν ταιριάζει σε προκαθορισμένο)
    if (_distance.km != null) {
      _kmCtrl.text = _distance.km!.toInt().toString();
    }
  }

  @override
  void dispose() {
    _kmCtrl.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _distance = SearchDistance.all;
      _sort = SearchSort.recent;
      _tagFilter = null;
      _kmCtrl.clear();
      _useCustomKm = false;
    });
  }

  void _apply() {
    // Αν έχει custom km, χρησιμοποίησέ το
    if (_useCustomKm && _kmCtrl.text.isNotEmpty) {
      final km = int.tryParse(_kmCtrl.text);
      if (km != null && km > 0) {
        // FIX: static method του extension -> SearchDistanceX, όχι SearchDistance
        _distance = SearchDistanceX.fromCustomKm(km.toDouble());
      }
    }
    widget.onApply(_distance, _sort, _tagFilter);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.tune, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(AppStrings.filters,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: _reset,
                  child: Text(AppStrings.clearFilters,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 0),

          // Content (scrollable)
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              children: [
                _SectionTitle(
                    icon: Icons.location_on_outlined,
                    title: 'filters.distance'.tr()),
                const SizedBox(height: 12),

                // Quick picks (1, 5, 10, 50, Παντού)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: SearchDistance.values
                      .where((d) => !d.isCustom)
                      .map((d) => _BigChip(
                            label: d.label,
                            selected: _distance == d && !_useCustomKm,
                            onTap: () => setState(() {
                              _distance = d;
                              _useCustomKm = false;
                              _kmCtrl.clear();
                            }),
                          ))
                      .toList(),
                ),

                const SizedBox(height: 16),

                // Custom km input
                Text('filters.customRadius'.tr(),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _kmCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        style: const TextStyle(color: AppColors.textPrimary),
                        onChanged: (v) {
                          setState(() {
                            _useCustomKm = v.isNotEmpty;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'filters.kmHint'.tr(),
                          prefixIcon: const Icon(Icons.radio_button_unchecked,
                              color: AppColors.textSecondary, size: 18),
                          suffixIcon: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Center(
                              widthFactor: 1,
                              child: Text('dist.km'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: _useCustomKm
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: _useCustomKm ? 1.5 : 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // === Ταξινόμηση ===
                _SectionTitle(icon: Icons.sort, title: 'filters.sort'.tr()),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _BigChip(
                        label: 'filters.sortRecent'.tr(),
                        selected: _sort == SearchSort.recent,
                        onTap: () => setState(() => _sort = SearchSort.recent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BigChip(
                        label: 'filters.sortNearest'.tr(),
                        selected: _sort == SearchSort.nearest,
                        onTap: () => setState(() => _sort = SearchSort.nearest),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // === Trending tags ===
                if (widget.trendingTags.isNotEmpty) ...[
                  _SectionTitle(
                      icon: Icons.local_fire_department,
                      title: 'filters.popularTags'.tr()),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _BigChip(
                        label: 'filters.tagAll'.tr(),
                        selected: _tagFilter == null,
                        onTap: () => setState(() => _tagFilter = null),
                      ),
                      ...widget.trendingTags.map((tag) => _BigChip(
                            label: '#$tag',
                            selected: _tagFilter == tag,
                            onTap: () => setState(() =>
                                _tagFilter = _tagFilter == tag ? null : tag),
                          )),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Apply button (sticky bottom)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border:
                  Border(top: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: SafeArea(
              top: false,
              child: ElevatedButton(
                onPressed: _apply,
                child: Text(AppStrings.applyFilters),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 16),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _BigChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BigChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 0.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}
