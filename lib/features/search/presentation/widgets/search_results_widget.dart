import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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
          child: const Text('Δοκίμασε ξανά'),
        ),
      ]));
    }

    if (state.query.isEmpty) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search, color: AppColors.textHint, size: 48),
        SizedBox(height: 12),
        Text('Γράψε κάτι για να ψάξεις.',
            style: TextStyle(color: AppColors.textHint)),
        SizedBox(height: 8),
        Text('π.χ. σκύλος, τρυπάνι, μαθήματα...',
            style: TextStyle(
                color: AppColors.textHint, fontSize: 12)),
      ]));
    }

    if (state.results.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off,
            color: AppColors.textHint, size: 48),
        const SizedBox(height: 12),
        Text('Δεν βρέθηκαν αγγελίες για "${state.query}"',
            style: const TextStyle(
                color: AppColors.textSecondary),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
          'Δοκίμασε διαφορετικές λέξεις ή αύξησε την απόσταση.',
          style: TextStyle(
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
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return null;
      }
      if (perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }
}