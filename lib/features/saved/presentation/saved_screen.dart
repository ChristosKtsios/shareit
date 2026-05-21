import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/listing_card.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../providers/saved_provider.dart';

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAsync = ref.watch(savedListingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Αποθηκευμένες')),
      body: savedAsync.when(
        loading: () => const ShimmerList(count: 4),
        error: (_, __) => const Center(
            child: Text('Σφάλμα φόρτωσης.',
                style: TextStyle(color: AppColors.textSecondary))),
        data: (listings) {
          if (listings.isEmpty) {
            return const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bookmark_outline, color: AppColors.textHint, size: 48),
              SizedBox(height: 12),
              Text('Δεν έχεις αποθηκευμένες αγγελίες.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ]),
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
