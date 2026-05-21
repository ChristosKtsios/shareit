import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../../../core/services/fcm_service.dart';

final authRepoProvider       = Provider<AuthRepository>((ref) => AuthRepository());
final authRepositoryProvider = authRepoProvider;

final authStateProvider = StreamProvider<User?>((ref) {
  final stream = ref.watch(authRepoProvider).authStateChanges;

  // Όταν συνδέεται ο χρήστης → init FCM
  stream.listen((user) {
    if (user != null) {
      FcmService.init(user.uid);
    }
  });

  return stream;
});

final currentUserProvider = Provider<User?>((ref) =>
    ref.watch(authStateProvider).valueOrNull);