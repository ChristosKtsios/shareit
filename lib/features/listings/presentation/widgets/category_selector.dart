import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/listing_model.dart';

/// Εικονίδιο + μεταφρασμένη ετικέτα ανά κατηγορία — σε ξεχωριστό, UI-layer
/// αρχείο (όχι στο listing_model.dart) ώστε το data model να μη χρειάζεται
/// εξάρτηση στο Flutter/Material.
extension ListingCategoryX on ListingCategory {
  IconData get icon {
    switch (this) {
      case ListingCategory.electronics:
        return Icons.devices_other_outlined;
      case ListingCategory.furniture:
        return Icons.chair_outlined;
      case ListingCategory.clothing:
        return Icons.checkroom_outlined;
      case ListingCategory.books:
        return Icons.menu_book_outlined;
      case ListingCategory.sports:
        return Icons.sports_soccer_outlined;
      case ListingCategory.kids:
        return Icons.toys_outlined;
      case ListingCategory.tools:
        return Icons.handyman_outlined;
      case ListingCategory.transport:
        return Icons.pedal_bike_outlined;
      case ListingCategory.services:
        return Icons.handshake_outlined;
      case ListingCategory.other:
        return Icons.category_outlined;
    }
  }

  String get label => 'category.$name'.tr();
}

/// Επιλογέας κατηγορίας αγγελίας — ίδιο visual language με τα chips φίλτρων
/// (feed_filters_sheet.dart), χρησιμοποιείται στη δημιουργία/επεξεργασία
/// αγγελίας ΚΑΙ στο φίλτρο του feed.
class CategorySelector extends StatelessWidget {
  final ListingCategory? selected;
  final ValueChanged<ListingCategory> onSelect;

  const CategorySelector({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ListingCategory.values.map((c) {
        final isSelected = c == selected;
        return GestureDetector(
          onTap: () => onSelect(c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 1.5 : 0.5,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(c.icon,
                  size: 15,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(c.label,
                  style: TextStyle(
                      color:
                          isSelected ? AppColors.primary : AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal)),
            ]),
          ),
        );
      }).toList(),
    );
  }
}
