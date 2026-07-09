import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/listing_card.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/saved_provider.dart';

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAsync = ref.watch(savedListingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('saved.title'.tr())),
      body: savedAsync.when(
        loading: () => const ShimmerList(count: 4),
        error: (_, __) => Center(
            child: Text('notif.loadError'.tr(),
                style: const TextStyle(color: AppColors.textSecondary))),
        data: (listings) {
          if (listings.isEmpty) {
            return EmptyState(
              icon: Icons.bookmark_outline,
              title: 'saved.emptyTitle'.tr(),
              subtitle: 'saved.emptySubtitle'.tr(),
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
