import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/user_model.dart';
import '../data/user_repository.dart';
import '../../auth/providers/auth_provider.dart';

final userRepoProvider = Provider<UserRepository>((ref) => UserRepository());

final currentUserDataProvider = StreamProvider<UserModel?>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream<UserModel?>.empty();
  return ref.watch(userRepoProvider).watch(uid);
});

final userByIdProvider = StreamProvider.family<UserModel?, String>((ref, uid) =>
    ref.watch(userRepoProvider).watch(uid));
