import 'package:cloud_firestore/cloud_firestore.dart';

enum ListingType { offer, seek }

class ListingModel {
  final String id, userId, userFirstName;
  final String? userAvatarUrl;
  final ListingType type;
  final String title, description, locationLabel;
  final List<String> imageUrls, tags, searchKeywords;
  final GeoPoint location;

  /// Έναρξη διαθεσιμότητας (μπορεί να περιλαμβάνει και ώρα)
  final DateTime? availableFrom;

  /// Λήξη διαθεσιμότητας (μπορεί να περιλαμβάνει και ώρα)
  final DateTime? availableUntil;

  /// True αν ο χρήστης συμπλήρωσε ώρα στο availableFrom
  final bool hasFromTime;

  /// True αν ο χρήστης συμπλήρωσε ώρα στο availableUntil
  final bool hasUntilTime;
  final bool autoDelete, isActive, isReported;
  final double rating;
  final DateTime createdAt;

  const ListingModel({
    required this.id,
    required this.userId,
    required this.userFirstName,
    this.userAvatarUrl,
    required this.type,
    required this.title,
    required this.description,
    required this.locationLabel,
    this.imageUrls = const [],
    this.tags = const [],
    this.searchKeywords = const [],
    required this.location,
    this.availableFrom,
    this.availableUntil,
    this.hasFromTime = false,
    this.hasUntilTime = false,
    required this.autoDelete,
    required this.isActive,
    this.isReported = false,
    required this.rating,
    required this.createdAt,
  });

  static List<String> generateKeywords(String title, String desc) =>
      '$title $desc'
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\sα-ωάέήίόύώϊϋΐΰ]', unicode: true), '')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 2)
          .toSet()
          .toList();

  static String normalizeTag(String tag) {
    var t = tag.trim().toLowerCase();
    if (t.startsWith('#')) t = t.substring(1);
    return t.replaceAll(RegExp(r'\s+'), '_');
  }

  factory ListingModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ListingModel(
      id: doc.id,
      userId: d['userId'] ?? '',
      userFirstName: d['userFirstName'] ?? '',
      userAvatarUrl: d['userAvatarUrl'],
      type: d['type'] == 'offer' ? ListingType.offer : ListingType.seek,
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      locationLabel: d['locationLabel'] ?? '',
      imageUrls: List<String>.from(d['imageUrls'] ?? []),
      tags: List<String>.from(d['tags'] ?? []),
      searchKeywords: List<String>.from(d['searchKeywords'] ?? []),
      location: d['location'] as GeoPoint,
      availableFrom: (d['availableFrom'] as Timestamp?)?.toDate(),
      availableUntil: (d['availableUntil'] as Timestamp?)?.toDate(),
      hasFromTime: d['hasFromTime'] ?? false,
      hasUntilTime: d['hasUntilTime'] ?? false,
      autoDelete: d['autoDelete'] ?? false,
      rating: (d['rating'] ?? 0).toDouble(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: d['isActive'] ?? true,
      isReported: d['isReported'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'userFirstName': userFirstName,
        'userAvatarUrl': userAvatarUrl,
        'type': type.name,
        'title': title,
        'description': description,
        'locationLabel': locationLabel,
        'imageUrls': imageUrls,
        'tags': tags,
        'searchKeywords': searchKeywords,
        'location': location,
        'availableFrom':
            availableFrom != null ? Timestamp.fromDate(availableFrom!) : null,
        'availableUntil':
            availableUntil != null ? Timestamp.fromDate(availableUntil!) : null,
        'hasFromTime': hasFromTime,
        'hasUntilTime': hasUntilTime,
        'autoDelete': autoDelete,
        'rating': rating,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': isActive,
        'isReported': isReported,
      };
}
