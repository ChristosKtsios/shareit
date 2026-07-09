import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/services/location_permission_gate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/listing_card.dart';
import '../../../../core/widgets/shimmer_loader.dart';
import '../../providers/search_provider.dart';

class SearchResultsWidget extends StatelessWidget {
  final SearchState state;
  final SearchNotifier notifier;

  const SearchResultsWidget({
    super.key,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    if (state.loading) return const ShimmerList(count: 4);

    if (state.error != null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline,
            color: AppColors.danger, size: 40),
        const SizedBox(height: 12),
        Text(state.error!,
            style: const TextStyle(
                color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => notifier.search(state.query),
          child: Text('srch.tryAgain'.tr()),
        ),
      ]));
    }

    // Prompt μόνο όταν δεν υπάρχει ΤΙΠΟΤΑ προς αναζήτηση — ίδια λογική με το
    // search() (query ΚΑΙ tags κενά). Αλλιώς (π.χ. tag-only search) θα κρύβαμε
    // αποτελέσματα ενώ ο μετρητής θα έδειχνε «1 αποτέλεσμα».
    if (state.query.isEmpty && state.tags.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search, color: AppColors.textHint, size: 48),
        const SizedBox(height: 12),
        Text('srch.searchPrompt'.tr(),
            style: const TextStyle(color: AppColors.textHint)),
        const SizedBox(height: 8),
        Text('srch.searchExamples'.tr(),
            style: const TextStyle(
                color: AppColors.textHint, fontSize: 12)),
      ]));
    }

    if (state.results.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off,
            color: AppColors.textHint, size: 48),
        const SizedBox(height: 12),
        Text('srch.noResults'.tr(namedArgs: {'q': state.query}),
            style: const TextStyle(
                color: AppColors.textSecondary),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'srch.noResultsHint'.tr(),
          style: const TextStyle(
              color: AppColors.textHint, fontSize: 12),
          textAlign: TextAlign.center),
      ]));
    }

    return FutureBuilder<Position?>(
      future: _getCurrentPosition(),
      builder: (context, posSnap) {
        final pos = posSnap.data;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: state.results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final l = state.results[i];
            double? distKm;
            if (pos != null) {
              final meters = Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                l.location.latitude,
                l.location.longitude,
              );
              distKm = meters / 1000;
            }
            return ListingCard(
              listing: l,
              distanceKm: distKm,
              onTap: () => context.push('/listing/${l.id}'),
            );
          },
        );
      },
    );
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final perm = await LocationPermissionGate.ensure();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      // Γρήγορο: τελευταία γνωστή θέση (ακαριαία) για την εμφάνιση απόστασης
      // στις κάρτες — αν λείπει, πέφτουμε σε medium fix με timeout.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}