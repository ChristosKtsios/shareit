import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid, firstName, lastName, email, phone;
  final double rating;
  final int ratingCount;
  final String? avatarUrl, fcmToken;
  final bool isVerified;
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

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      firstName: d['firstName'] ?? '',
      lastName: d['lastName'] ?? '',
      email: d['email'] ?? '',
      phone: d['phone'] ?? '',
      rating: (d['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
      avatarUrl: d['avatarUrl'] ?? d['photoUrl'],
      fcmToken: d['fcmToken'],
      isVerified: d['isVerified'] ?? false,
      blockedUids: List<String>.from(d['blockedUids'] ?? []),
      savedListingIds: List<String>.from(d['savedListingIds'] ?? []),
      photos: List<String>.from(d['photos'] ?? []),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastSeen: (d['lastSeen'] as Timestamp?)?.toDate(),
      showOnlineStatus: d['showOnlineStatus'] ?? true,
      isPrivateProfile: d['isPrivateProfile'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'rating': rating,
        'ratingCount': ratingCount,
        'avatarUrl': avatarUrl,
        'fcmToken': fcmToken,
        'isVerified': isVerified,
        'blockedUids': blockedUids,
        'savedListingIds': savedListingIds,
        'photos': photos,
        'createdAt': FieldValue.serverTimestamp(),
        'isPrivateProfile': isPrivateProfile,
        'showOnlineStatus': showOnlineStatus,
      };
}
