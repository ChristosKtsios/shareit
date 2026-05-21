import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/deal_model.dart';
import '../data/deal_repository.dart';
import '../../auth/providers/auth_provider.dart';

final dealRepoProvider = Provider<DealRepository>((ref) => DealRepository());

// Deals του τρέχοντος χρήστη
final myDealsProvider = StreamProvider<List<DealModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream<List<DealModel>>.empty();
  return ref.watch(dealRepoProvider).watchUserDeals(uid);
});

// Active deals μόνο
final myActiveDealsProvider = StreamProvider<List<DealModel>>((ref) {
  final deals = ref.watch(myDealsProvider);
  return deals.when(
    data: (list) => Stream.value(
        list.where((d) => d.status == DealStatus.active).toList()),
    loading: () => const Stream<List<DealModel>>.empty(),
    error:   (_, __) => const Stream<List<DealModel>>.empty(),
  );
});

// Deal από chatId
final dealByChatProvider = StreamProvider.family<DealModel?, String>(
    (ref, chatId) =>
        ref.watch(dealRepoProvider).watchByChatId(chatId));

// Pending deals — περιμένουν αποδοχή
final myPendingDealsProvider = StreamProvider<List<DealModel>>((ref) {
  final deals = ref.watch(myDealsProvider);
  return deals.when(
    data: (list) => Stream.value(
        list.where((d) => d.status == DealStatus.pending).toList()),
    loading: () => const Stream<List<DealModel>>.empty(),
    error:   (_, __) => const Stream<List<DealModel>>.empty(),
  );
});