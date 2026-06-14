import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Cache για user data (firstName, lastName, avatarUrl) ώστε ο χάρτης
/// να μη χρειάζεται να κάνει query για κάθε marker.
///
/// Χρήση:
///   final user = await UserMapCache.get('uid123');
///   if (user != null) print(user.fullName);
///
/// Ένας χρήστης queryάρεται **μία φορά**, ακόμα κι αν έχει 50 αγγελίες
/// στον χάρτη.
class UserMapCache {
  UserMapCache._();

  static final Map<String, UserMapInfo> _cache = {};
  static final Map<String, Future<UserMapInfo?>> _pending = {};

  /// Επιστρέφει user info από cache ή κάνει query. null αν δεν υπάρχει.
  static Future<UserMapInfo?> get(String uid) async {
    if (uid.isEmpty) return null;

    // Cached
    final cached = _cache[uid];
    if (cached != null) return cached;

    // Ήδη γίνεται query για αυτόν τον uid -> περίμενε
    final pending = _pending[uid];
    if (pending != null) return pending;

    // Νέο query
    final future = _fetch(uid);
    _pending[uid] = future;

    final result = await future;
    _pending.remove(uid);
    if (result != null) _cache[uid] = result;
    return result;
  }

  static Future<UserMapInfo?> _fetch(String uid) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      final d = doc.data() as Map<String, dynamic>;
      return UserMapInfo(
        uid: uid,
        firstName: (d['firstName'] as String?) ?? '',
        lastName: (d['lastName'] as String?) ?? '',
        avatarUrl: (d['avatarUrl'] as String?) ?? (d['photoUrl'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  /// Πάρε από cache συγχρόνως (χωρίς query). null αν δεν είναι cached.
  static UserMapInfo? getCachedSync(String uid) => _cache[uid];

  /// Καθαρισμός cache (π.χ. μετά από logout).
  static void clear() {
    _cache.clear();
    _pending.clear();
  }

  /// Καθαρισμός cache για συγκεκριμένο χρήστη (π.χ. όταν αλλάζει profile).
  static void invalidate(String uid) {
    _cache.remove(uid);
  }
}

class UserMapInfo {
  final String uid, firstName, lastName;
  final String? avatarUrl;

  const UserMapInfo({
    required this.uid,
    required this.firstName,
    required this.lastName,
    this.avatarUrl,
  });

  String get fullName {
    if (firstName.isEmpty && lastName.isEmpty) return '';
    if (lastName.isEmpty) return firstName;
    return '$firstName $lastName';
  }

  String get initial {
    if (firstName.isNotEmpty) return firstName[0].toUpperCase();
    if (lastName.isNotEmpty) return lastName[0].toUpperCase();
    return '?';
  }
}
