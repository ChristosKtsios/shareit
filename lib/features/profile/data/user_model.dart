import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid, firstName, lastName, email, phone;
  final double rating;
  final int ratingCount;
  final String? avatarUrl, fcmToken;
  final bool isVerified;

  /// Επαληθευμένο κινητό μέσω OTP — η **μοναδική** πηγή αλήθειας για το αν ο
  /// χρήστης θεωρείται «επαληθευμένος». (Το [isVerified] μπαίνει `true` σε κάθε
  /// εγγραφή/Google sign-in, οπότε δεν είναι σήμα εμπιστοσύνης.)
  final bool phoneVerified;
  final List<String> blockedUids, savedListingIds;
  final List<String> photos;
  final DateTime createdAt;
  final DateTime? lastSeen;
  final bool showOnlineStatus;
  final bool isPrivateProfile;

  const UserModel({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.rating,
    required this.ratingCount,
    this.avatarUrl,
    this.fcmToken,
    this.isVerified = false,
    this.phoneVerified = false,
    this.blockedUids = const [],
    this.savedListingIds = const [],
    this.photos = const [],
    required this.createdAt,
    this.lastSeen,
    this.showOnlineStatus = true,
    this.isPrivateProfile = false,
  });

  String get fullName => '$firstName $lastName';
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
          .toUpperCase();

  bool get isOnline {
    if (!showOnlineStatus || lastSeen == null) return false;
    return DateTime.now().difference(lastSeen!).inMinutes < 5;
  }

  /// [private] = το `users/{uid}/private/data` doc. Το διαβάζει **μόνο ο ίδιος**
  /// ο χρήστης (βλ. firestore.rules) — εκεί ζουν πλέον email/phone/fcmToken,
  /// ώστε να μην κατεβαίνουν στους άλλους μαζί με το δημόσιο προφίλ. Για ξένα
  /// προφίλ το [private] είναι `null` και τα πεδία μένουν κενά.
  factory UserModel.fromFirestore(DocumentSnapshot doc,
      [Map<String, dynamic>? private]) {
    final d = doc.data() as Map<String, dynamic>;
    final p = private ?? const <String, dynamic>{};
    return UserModel(
      uid: doc.id,
      firstName: d['firstName'] ?? '',
      lastName: d['lastName'] ?? '',
      email: p['email'] ?? '',
      phone: p['phone'] ?? '',
      rating: (d['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
      avatarUrl: d['avatarUrl'] ?? d['photoUrl'],
      fcmToken: p['fcmToken'],
      isVerified: d['isVerified'] ?? false,
      phoneVerified: d['phoneVerified'] ?? false,
      blockedUids: List<String>.from(d['blockedUids'] ?? []),
      savedListingIds: List<String>.from(d['savedListingIds'] ?? []),
      photos: List<String>.from(d['photos'] ?? []),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastSeen: (d['lastSeen'] as Timestamp?)?.toDate(),
      showOnlineStatus: d['showOnlineStatus'] ?? true,
      isPrivateProfile: d['isPrivateProfile'] ?? false,
    );
  }

  /// ΠΡΟΣΟΧΗ: τα email/phone/fcmToken **δεν** ανήκουν εδώ — γράφονται στο
  /// `users/{uid}/private/data` (UserRepository.updatePrivate). Τα rules
  /// απορρίπτουν write αυτών των πεδίων στο δημόσιο doc.
  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'firstName': firstName,
        'lastName': lastName,
        'rating': rating,
        'ratingCount': ratingCount,
        'avatarUrl': avatarUrl,
        'isVerified': isVerified,
        'phoneVerified': phoneVerified,
        'blockedUids': blockedUids,
        'savedListingIds': savedListingIds,
        'photos': photos,
        'createdAt': FieldValue.serverTimestamp(),
        'isPrivateProfile': isPrivateProfile,
        'showOnlineStatus': showOnlineStatus,
      };
}
