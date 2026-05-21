import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../data/listing_model.dart';
import '../data/listing_repository.dart';
import 'widgets/listing_header_widget.dart';
import 'widgets/listing_images_widget.dart';
import 'widgets/listing_info_widget.dart';
import 'widgets/listing_actions_widget.dart';

final _listingDetailProvider =
    FutureProvider.family<ListingModel?, String>((ref, id) =>
        ListingRepository().getListingById(id));

class ListingDetailScreen extends ConsumerWidget {
  final String listingId;
  const ListingDetailScreen({super.key, required this.listingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingAsync = ref.watch(_listingDetailProvider(listingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Αγγελία')),
      body: listingAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const Center(
            child: Text(AppStrings.errorGeneric,
                style: TextStyle(color: AppColors.textSecondary))),
        data: (listing) {
          if (listing == null) {
            return const Center(
              child: Text('Η αγγελία δεν βρέθηκε.',
                  style: TextStyle(color: AppColors.textSecondary)));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Τίτλος + tags + περιγραφή
                ListingHeaderWidget(listing: listing),

                // Φωτογραφίες
                ListingImagesWidget(listing: listing),

                // Πληροφορίες χρήστη + τοποθεσία + ημ/νία
                ListingInfoWidget(listing: listing),

                // Κουμπιά ενεργειών
                ListingActionsWidget(listing: listing),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}