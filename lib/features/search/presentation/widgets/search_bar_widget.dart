import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

class SearchBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// ✨ Αναζήτηση με AI (φυσική γλώσσα). Καλείται και από το «Enter» του
  /// πληκτρολογίου. null → δεν εμφανίζεται το κουμπί.
  final ValueChanged<String>? onAiSearch;
  final bool aiLoading;

  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.onAiSearch,
    this.aiLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: AppStrings.searchHint,
          prefixIcon: const Icon(Icons.search,
              color: AppColors.textSecondary, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  if (onAiSearch != null)
                    aiLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary)),
                          )
                        : IconButton(
                            tooltip: 'srch.aiButton'.tr(),
                            icon: const Icon(Icons.auto_awesome,
                                color: AppColors.primary, size: 20),
                            onPressed: () => onAiSearch!(controller.text)),
                  IconButton(
                      icon: const Icon(Icons.clear,
                          color: AppColors.textSecondary, size: 18),
                      onPressed: onClear),
                ])
              : null,
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
        ),
        onChanged: onChanged,
        textInputAction:
            onAiSearch != null ? TextInputAction.search : null,
        onSubmitted: onAiSearch,
      ),
    );
  }
}