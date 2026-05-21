import 'package:cloud_firestore/cloud_firestore.dart';

enum DealStatus { pending, accepted, active, completed, cancelled }

class DealProposal {
  final String userId;
  final String reason;
  final String iGive;
  final String iReceive;
  final DateTime deliveryAt;
  final bool withPayment;
  final double? amount;
  final bool accepted;

  const DealProposal({
    required this.userId,
    required this.reason,
    required this.iGive,
    required this.iReceive,
    required this.deliveryAt,
    required this.withPayment,
    this.amount,
    this.accepted = false,
  });

  DealProposal copyWith({bool? accepted}) => DealProposal(
    userId:      userId,
    reason:      reason,
    iGive:       iGive,
    iReceive:    iReceive,
    deliveryAt:  deliveryAt,
    withPayment: withPayment,
    amount:      amount,
    accepted:    accepted ?? this.accepted,
  );

  factory DealProposal.fromMap(Map<String, dynamic> d) => DealProposal(
    userId:      d['userId']      ?? '',
    reason:      d['reason']      ?? '',
    iGive:       d['iGive']       ?? '',
    iReceive:    d['iReceive']    ?? '',
    deliveryAt:  (d['deliveryAt'] as Timestamp).toDate(),
    withPayment: d['withPayment'] ?? false,
    amount:      (d['amount']     as num?)?.toDouble(),
    accepted:    d['accepted']    ?? false,
  );

  Map<String, dynamic> toMap() => {
    'userId':      userId,
    'reason':      reason,
    'iGive':       iGive,
    'iReceive':    iReceive,
    'deliveryAt':  Timestamp.fromDate(deliveryAt),
    'withPayment': withPayment,
    'amount':      amount,
    'accepted':    accepted,
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
  final DateTime? deliveryAt;
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
    this.deliveryAt,
    this.ownerRating,
    this.seekerRating,
    required this.createdAt,
  });

  bool get isActive      => status == DealStatus.active;
  bool get bothAccepted  =>
      proposal1?.accepted == true && proposal2?.accepted == true;
  Duration get remaining =>
      deliveryAt?.difference(DateTime.now()) ?? Duration.zero;
  bool get isExpired     => remaining.isNegative;

  factory DealModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DealModel(
      id:           doc.id,
      chatId:       d['chatId']       ?? '',
      listingId:    d['listingId']    ?? '',
      listingTitle: d['listingTitle'] ?? '',
      user1Uid:     d['user1Uid']     ?? '',
      user2Uid:     d['user2Uid']     ?? '',
      status: DealStatus.values.firstWhere(
          (e) => e.name == d['status'],
          orElse: () => DealStatus.pending),
      proposal1: d['proposal1'] != null
          ? DealProposal.fromMap(d['proposal1']) : null,
      proposal2: d['proposal2'] != null
          ? DealProposal.fromMap(d['proposal2']) : null,
      activatedAt:  (d['activatedAt']  as Timestamp?)?.toDate(),
      deliveryAt:   (d['deliveryAt']   as Timestamp?)?.toDate(),
      ownerRating:  (d['ownerRating']  as num?)?.toDouble(),
      seekerRating: (d['seekerRating'] as num?)?.toDouble(),
      createdAt:    (d['createdAt']    as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'chatId':       chatId,
    'listingId':    listingId,
    'listingTitle': listingTitle,
    'user1Uid':     user1Uid,
    'user2Uid':     user2Uid,
    'status':       status.name,
    'proposal1':    proposal1?.toMap(),
    'proposal2':    proposal2?.toMap(),
    'activatedAt':  activatedAt != null
        ? Timestamp.fromDate(activatedAt!) : null,
    'deliveryAt':   deliveryAt != null
        ? Timestamp.fromDate(deliveryAt!) : null,
    'ownerRating':  ownerRating,
    'seekerRating': seekerRating,
    'createdAt':    FieldValue.serverTimestamp(),
  };
}