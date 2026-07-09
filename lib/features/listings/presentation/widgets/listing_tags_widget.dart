import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/listing_model.dart';
import '../../data/tags_repository.dart';

class ListingTagsWidget extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<List<String>> onTagsChanged;
  final int minTags;
  final int maxTags;

  /// Προτεινόμενα tags από τίτλο/περιγραφή (auto-suggest)
  final List<String> suggestedFromText;

  const ListingTagsWidget({
    super.key,
    required this.tags,
    required this.onTagsChanged,
    this.minTags = 3,
    this.maxTags = 10,
    this.suggestedFromText = const [],
  });

  @override
  State<ListingTagsWidget> createState() => _ListingTagsWidgetState();
}

class _ListingTagsWidgetState extends State<ListingTagsWidget> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  final _repo = TagsRepository();

  List<TagSuggestion> _suggestions = [];
  List<TagSuggestion> _trending = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    try {
      final t = await _repo.getTrendingTags(limit: 8);
      if (mounted) setState(() => _trending = t);
    } catch (_) {}
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (value.trim().isEmpty) {
        setState(() => _suggestions = []);
        return;
      }
      try {
        final results = await _repo.searchTags(value);
        if (mounted) {
          setState(() => _suggestions =
              results.where((s) => !widget.tags.contains(s.name)).toList());
        }
      } catch (_) {}
    });
  }

  void _addTag(String raw) {
    final tag = ListingModel.normalizeTag(raw);
    if (tag.isEmpty) return;
    if (widget.tags.contains(tag)) {
      _ctrl.clear();
      setState(() => _suggestions = []);
      return;
    }
    if (widget.tags.length >= widget.maxTags) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('ltags.maxTags'
                .tr(namedArgs: {'n': '${widget.maxTags}'}))),
      );
      return;
    }
    final newTags = [...widget.tags, tag];
    widget.onTagsChanged(newTags);
    _ctrl.clear();
    setState(() => _suggestions = []);
  }

  void _removeTag(String tag) {
    final newTags = widget.tags.where((t) => t != tag).toList();
    widget.onTagsChanged(newTags);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.minTags - widget.tags.length;
    final unusedAutoSuggestions = widget.suggestedFromText
        .where((s) => !widget.tags.contains(s))
        .take(8)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ltags.searchTags'.tr(),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            Text(
              '${widget.tags.length}/${widget.maxTags}',
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          remaining > 0
              ? 'ltags.addMore'.tr(namedArgs: {'n': '$remaining'})
              : 'ltags.canAddMore'.tr(
                  namedArgs: {'n': '${widget.maxTags - widget.tags.length}'}),
          style: TextStyle(
              color: remaining > 0 ? AppColors.deal : AppColors.textHint,
              fontSize: 11),
        ),
        const SizedBox(height: 12),

        // Selected tags
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.tags
                .map((tag) => _SelectedTagChip(
                      tag: tag,
                      onRemove: () => _removeTag(tag),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],

        // Input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                style: const TextStyle(color: AppColors.textPrimary),
                onChanged: _onChanged,
                onSubmitted: _addTag,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'ltags.inputHint'.tr(),
                  prefixIcon: const Icon(Icons.tag,
                      color: AppColors.textSecondary, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _addTag(_ctrl.text),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),

        // Autocomplete suggestions από υπάρχοντα tags
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              children: _suggestions
                  .map((s) => _SuggestionTile(
                        suggestion: s,
                        onTap: () => _addTag(s.name),
                      ))
                  .toList(),
            ),
          ),
        ],

        // Auto-suggestions από τίτλο/περιγραφή
        if (unusedAutoSuggestions.isNotEmpty && _suggestions.isEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.primary, size: 14),
              const SizedBox(width: 4),
              Text(
                'ltags.fromDescription'.tr(),
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: unusedAutoSuggestions
                .map((s) => _AutoSuggestChip(
                      tag: s,
                      onTap: () => _addTag(s),
                    ))
                .toList(),
          ),
        ],

        // Trending tags
        if (_trending.isNotEmpty && _suggestions.isEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  color: AppColors.deal, size: 14),
              const SizedBox(width: 4),
              Text(
                'ltags.popular'.tr(),
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _trending
                .where((t) => !widget.tags.contains(t.name))
                .map((s) => _TrendingChip(
                      suggestion: s,
                      onTap: () => _addTag(s.name),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _SelectedTagChip extends StatelessWidget {
  final String tag;
  final VoidCallback onRemove;
  const _SelectedTagChip({required this.tag, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('#$tag',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: AppColors.primary, size: 16),
          ),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final TagSuggestion suggestion;
  final VoidCallback onTap;
  const _SuggestionTile({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.tag, color: AppColors.textSecondary, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(suggestion.name,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14)),
            ),
            Text(
              'ltags.listingCount'
                  .tr(namedArgs: {'n': '${suggestion.count}'}),
              style: const TextStyle(color: AppColors.textHint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoSuggestChip extends StatelessWidget {
  final String tag;
  final VoidCallback onTap;
  const _AutoSuggestChip({required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.4),
              width: 1,
              style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, color: AppColors.primary, size: 12),
            const SizedBox(width: 4),
            Text(tag,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _TrendingChip extends StatelessWidget {
  final TagSuggestion suggestion;
  final VoidCallback onTap;
  const _TrendingChip({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('#${suggestion.name}',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            Text('${suggestion.count}',
                style:
                    const TextStyle(color: AppColors.textHint, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
