import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../../../core/services/fcm_service.dart';
import '../../listings/data/listing_repository.dart';

final authRepoProvider       = Provider<AuthRepository>((ref) => AuthRepository());
final authRepositoryProvider = authRepoProvider;

final authStateProvider = StreamProvider<User?>((ref) {
  final stream = ref.watch(authRepoProvider).authStateChanges;

  stream.listen((user) {
    if (user != null) {
      // Όταν συνδέεται ο χρήστης → init FCM + καθάρισμα ληγμένων αγγελιών.
      // fire-and-forget → πρέπει να πιάνουμε σφάλματα (π.χ. IOException από
      // getToken σε κακό δίκτυο) ώστε να μη γίνονται unhandled fatal.
      FcmService.init(user.uid).catchError((_) {});
      ListingRepository().cleanupExpiredForUser(user.uid).catchError((_) => 0);
    }
  });

  return stream;
});

final currentUserProvider = Provider<User?>((ref) =>
    ref.watch(authStateProvider).valueOrNull);