import 'package:cloud_firestore/cloud_firestore.dart';

enum DealStatus { pending, accepted, active, completed, cancelled }

/// Πρόταση deal με 4 πεδία:
/// - title: τίτλος που ΠΡΕΠΕΙ να περιέχει @firstName lastName και των 2 χρηστών
/// - details: λεπτομέρειες/όροι της ανταλλαγής
/// - startDate: πότε ξεκινάει η ανταλλαγή
/// - endDate: πότε ολοκληρώνεται
/// - accepted: true όταν αυτός ο χρήστης έχει πατήσει "Συμφωνώ"
class DealProposal {
  final String userId;
  final String title;
  final String details;
  final DateTime startDate;
  final DateTime endDate;
  final bool accepted;

  const DealProposal({
    required this.userId,
    required this.title,
    required this.details,
    required this.startDate,
    required this.endDate,
    this.accepted = false,
  });

  DealProposal copyWith({bool? accepted}) => DealProposal(
        userId: userId,
        title: title,
        details: details,
        startDate: startDate,
        endDate: endDate,
        accepted: accepted ?? this.accepted,
      );

  factory DealProposal.fromMap(Map<String, dynamic> d) {
    // Safe parsing - αν λείπει κάποιο field, δίνει default
    final start = d['startDate'] as Timestamp?;
    final end = d['endDate'] as Timestamp?;
    return DealProposal(
      userId: d['userId'] as String? ?? '',
      title: d['title'] as String? ?? '',
      details: d['details'] as String? ?? d['description'] as String? ?? '',
      startDate: start?.toDate() ?? DateTime.now(),
      endDate: end?.toDate() ??
          (d['deliveryAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 1)),
      accepted: d['accepted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'title': title,
        'details': details,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'accepted': accepted,
      };
}

class DealModel {
  final String id;
  final String chatId;
  final String listingId;
  final String listingTitle;
  final String user1Uid;
  final String user2Uid;
  final DealStatus status;
  final DealProposal? proposal1;
  final DealProposal? proposal2;
  final DateTime? activatedAt;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? ownerRating;
  final double? seekerRating;
  final DateTime createdAt;

  const DealModel({
    required this.id,
    required this.chatId,
    required this.listingId,
    required this.listingTitle,
    required this.user1Uid,
    required this.user2Uid,
    required this.status,
    this.proposal1,
    this.proposal2,
    this.activatedAt,
    this.startDate,
    this.endDate,
    this.ownerRating,
    this.seekerRating,
    required this.createdAt,
  });

  bool get isActive => status == DealStatus.active;
  bool get isCompleted => status == DealStatus.completed;
  bool get bothAccepted =>
      proposal1?.accepted == true && proposal2?.accepted == true;

  Duration get remaining =>
      endDate?.difference(DateTime.now()) ?? Duration.zero;
  bool get isExpired => remaining.isNegative;

  bool get hasStarted =>
      startDate != null && startDate!.isBefore(DateTime.now());

  String get displayTitle =>
      proposal1?.title ?? proposal2?.title ?? listingTitle;

  String get displayDetails => proposal1?.details ?? proposal2?.details ?? '';

  factory DealModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DealModel(
      id: doc.id,
      chatId: d['chatId'] as String? ?? '',
      listingId: d['listingId'] as String? ?? '',
      listingTitle: d['listingTitle'] as String? ?? '',
      user1Uid: d['user1Uid'] as String? ?? '',
      user2Uid: d['user2Uid'] as String? ?? '',
      status: DealStatus.values.firstWhere((e) => e.name == d['status'],
          orElse: () => DealStatus.pending),
      proposal1:
          d['proposal1'] != null ? DealProposal.fromMap(d['proposal1']) : null,
      proposal2:
          d['proposal2'] != null ? DealProposal.fromMap(d['proposal2']) : null,
      activatedAt: (d['activatedAt'] as Timestamp?)?.toDate(),
      startDate: (d['startDate'] as Timestamp?)?.toDate(),
      endDate: (d['endDate'] as Timestamp?)?.toDate() ??
          (d['deliveryAt'] as Timestamp?)?.toDate(),
      ownerRating: (d['ownerRating'] as num?)?.toDouble(),
      seekerRating: (d['seekerRating'] as num?)?.toDouble(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
