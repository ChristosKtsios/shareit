import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/listing_card.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../providers/listings_provider.dart';
import '../../../core/widgets/empty_state.dart';

class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(myListingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.myListings)),
      body: listingsAsync.when(
        loading: () => const ShimmerList(count: 4),
        error: (_, __) => Center(
            child: Text(AppStrings.errorGeneric,
                style: const TextStyle(color: AppColors.textSecondary))),
        data: (listings) {
          if (listings.isEmpty) {
            return EmptyState(
              icon: Icons.post_add_outlined,
              title: 'mylist.emptyTitle'.tr(),
              subtitle: 'mylist.emptySubtitle'.tr(),
              actionLabel: 'mylist.createListing'.tr(),
              onAction: () => context.push('/listing/new'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: listings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => ListingCard(
              listing: listings[i],
              onTap: () => context.push('/listing/${listings[i].id}'),
            ),
          );
        },
      ),
    );
  }
}
