import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../deals/providers/deal_provider.dart';
import '../../deals/data/deal_model.dart';

class ProfileScreen extends ConsumerWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';
    final targetUid  = userId ?? currentUid;
    final isMe       = targetUid == currentUid;

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users').doc(targetUid).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary));
          }

          final data        = snap.data!.data()
              as Map<String, dynamic>? ?? {};
          final firstName   = data['firstName']    as String? ?? '';
          final lastName    = data['lastName']     as String? ?? '';
          final rating      = (data['rating']      as num?)?.toDouble() ?? 0.0;
          final ratingCount = (data['ratingCount'] as num?)?.toInt()    ?? 0;
          final dealsCount  = (data['dealsCount']  as num?)?.toInt()    ?? 0;
          final isVerified  = data['isVerified']   as bool?   ?? false;
          final avatarUrl   = data['avatarUrl']    as String?;
          final friends     = List<String>.from(data['friends'] ?? []);
          final initials    = '${firstName.isNotEmpty ? firstName[0] : ''}'
              '${lastName.isNotEmpty ? lastName[0] : ''}'.toUpperCase();
          final isFriend    = friends.contains(currentUid);

          return CustomScrollView(slivers: [

            // ── Header ──
            SliverToBoxAdapter(child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 20, right: 20, bottom: 20,
              ),
              color: AppColors.surface,
              child: Column(children: [
                Row(children: [
                  UserAvatar(
                    initials:    initials,
                    avatarUrl:   avatarUrl,
                    radius:      36,
                    showVerified: isVerified),
                  const SizedBox(width: 16),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$firstName $lastName',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      _StarRating(
                          rating: rating,
                          count:  ratingCount),
                    ],
                  )),
                  if (isMe)
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          color: AppColors.textSecondary),
                      onPressed: () => context.push('/settings'),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.more_vert,
                          color: AppColors.textSecondary),
                      onPressed: () => _showOptions(
                          context, ref, targetUid,
                          currentUid, isFriend),
                    ),
                ]),

                const SizedBox(height: 16),

                // ── Stats row ──
                Row(children: [
                  _StatBox(
                    label: 'Deals',
                    value: '$dealsCount',
                    icon:  Icons.handshake_outlined,
                    color: AppColors.deal,
                  ),
                  const SizedBox(width: 10),
                  _StatBox(
                    label: 'Φίλοι',
                    value: '${friends.length}',
                    icon:  Icons.people_outline,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  _StatBox(
                    label: 'Αξιολόγηση',
                    value: rating.toStringAsFixed(1),
                    icon:  Icons.star_outline,
                    color: AppColors.offer,
                  ),
                ]),
              ]),
            )),

            // ── Active deals (μόνο για εμένα) ──
            if (isMe) SliverToBoxAdapter(child: Consumer(
              builder: (context, ref, _) {
                final dealsAsync = ref.watch(myActiveDealsProvider);
                return dealsAsync.when(
                  data: (deals) {
                    if (deals.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(
                              16, 16, 16, 8),
                          child: Text(AppStrings.activeDeals,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                        ...deals.map(
                            (d) => _ActiveDealTile(deal: d)),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error:   (_, __) => const SizedBox.shrink(),
                );
              },
            )),

            // ── Wall title ──
            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text(AppStrings.wall,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            )),

            // ── Wall posts ──
            SliverToBoxAdapter(child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('wallPosts')
                  .where('targetUid', isEqualTo: targetUid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                      'Δεν υπάρχουν αξιολογήσεις ακόμα.',
                      style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 13)),
                );
                }
                return Column(
                  children: docs.map((doc) {
                    final d = doc.data()
                        as Map<String, dynamic>;
                    return _WallPost(
                        data:       d,
                        docId:      doc.id,
                        currentUid: currentUid);
                  }).toList(),
                );
              },
            )),

            const SliverToBoxAdapter(
                child: SizedBox(height: 32)),
          ]);
        },
      ),
    );
  }

  void _showOptions(
      BuildContext context,
      WidgetRef ref,
      String targetUid,
      String currentUid,
      bool isFriend) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min,
        children: [
          // Αφαίρεση φίλου
          if (isFriend) ListTile(
            leading: const Icon(Icons.person_remove_outlined,
                color: AppColors.textSecondary),
            title: const Text('Αφαίρεση φίλου',
                style: TextStyle(
                    color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              _removeFriend(currentUid, targetUid);
            },
          ),
          ListTile(
            leading: const Icon(Icons.block,
                color: AppColors.danger),
            title: const Text('Αποκλεισμός',
                style: TextStyle(color: AppColors.danger)),
            onTap: () {
              Navigator.pop(context);
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUid)
                  .update({
                'blockedUids':
                    FieldValue.arrayUnion([targetUid]),
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined,
                color: AppColors.textSecondary),
            title: const Text('Αναφορά',
                style: TextStyle(
                    color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              context.push('/report/user/$targetUid');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _removeFriend(
      String currentUid, String targetUid) async {
    final batch = FirebaseFirestore.instance.batch();

    batch.update(
      FirebaseFirestore.instance
          .collection('users').doc(currentUid),
      {'friends': FieldValue.arrayRemove([targetUid])},
    );

    batch.update(
      FirebaseFirestore.instance
          .collection('users').doc(targetUid),
      {'friends': FieldValue.arrayRemove([currentUid])},
    );

    await batch.commit();
  }
}

// ── Stats Box ──
class _StatBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(
          vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 0.5),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11)),
      ]),
    ),
  );
}

// ── Star Rating ──
class _StarRating extends StatelessWidget {
  final double rating;
  final int count;
  const _StarRating({required this.rating, required this.count});

  @override
  Widget build(BuildContext context) => Row(children: [
    ...List.generate(5, (i) => Icon(
      i < rating.floor()
          ? Icons.star
          : (i < rating ? Icons.star_half : Icons.star_border),
      color: AppColors.deal, size: 16)),
    const SizedBox(width: 4),
    Text('${rating.toStringAsFixed(1)} ($count)',
        style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12)),
  ]);
}

// ── Active Deal Tile ──
class _ActiveDealTile extends StatefulWidget {
  final DealModel deal;
  const _ActiveDealTile({required this.deal});
  @override
  State<_ActiveDealTile> createState() => _ActiveDealTileState();
}

class _ActiveDealTileState extends State<_ActiveDealTile> {
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.deal.remaining;
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _remaining = widget.deal.remaining);
      if (!_remaining.isNegative) _tick();
    });
  }

  String _formatTimer(Duration d) {
    if (d.isNegative) return 'Έληξε';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining.isNegative;
    final color   = expired ? AppColors.danger : AppColors.deal;

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              expired
                  ? Icons.check_circle_outline
                  : Icons.handshake_outlined,
              color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.deal.listingTitle,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500))),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatTimer(_remaining),
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [
                      FontFeature.tabularFigures()
                    ]),
              ),
            ),
          ]),

          if (widget.deal.deliveryAt != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.event_outlined,
                  color: AppColors.textHint, size: 13),
              const SizedBox(width: 4),
              Text(
                'Παράδοση: '
                '${widget.deal.deliveryAt!.day}/'
                '${widget.deal.deliveryAt!.month}/'
                '${widget.deal.deliveryAt!.year}  '
                '${widget.deal.deliveryAt!.hour.toString().padLeft(2, '0')}:'
                '${widget.deal.deliveryAt!.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11),
              ),
            ]),
          ],

          const SizedBox(height: 10),

          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () =>
                  context.push('/chat/${widget.deal.chatId}'),
              icon: const Icon(Icons.chat_bubble_outline,
                  size: 14, color: AppColors.primary),
              label: const Text('Συνομιλία',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(
                    color: AppColors.primary),
                padding: const EdgeInsets.symmetric(
                    vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: expired
                  ? () => context.push(
                      '/rate-deal/${widget.deal.id}')
                  : null,
              icon: Icon(Icons.star_outline,
                  size: 14,
                  color: expired
                      ? AppColors.deal
                      : AppColors.textHint),
              label: Text(
                expired ? 'Αξιολόγησε' : 'Σε εξέλιξη',
                style: TextStyle(
                    color: expired
                        ? AppColors.deal
                        : AppColors.textHint,
                    fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: expired
                        ? AppColors.deal
                        : AppColors.border),
                padding: const EdgeInsets.symmetric(
                    vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            )),
          ]),
        ],
      ),
    );
  }
}

// ── Wall Post ──
class _WallPost extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId, currentUid;
  const _WallPost({
    required this.data,
    required this.docId,
    required this.currentUid,
  });
  @override
  State<_WallPost> createState() => _WallPostState();
}

class _WallPostState extends State<_WallPost> {
  bool _expanded = false;
  final _ctrl    = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authorName   = widget.data['authorName']   as String? ?? '';
    final text         = widget.data['text']         as String? ?? '';
    final rating       = (widget.data['rating']      as num?)?.toDouble() ?? 0.0;
    final listingTitle = widget.data['listingTitle'] as String? ?? '';
    final dealStatus   = widget.data['dealStatus']   as String? ?? '';
    final initials     = authorName.isNotEmpty
        ? authorName[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            UserAvatar(initials: initials, radius: 14),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(authorName,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                if (dealStatus == 'active')
                  const Text('🤝 Deal σε εξέλιξη',
                      style: TextStyle(
                          color: AppColors.deal,
                          fontSize: 11))
                else if (dealStatus == 'completed')
                  const Text('✅ Ολοκληρώθηκε',
                      style: TextStyle(
                          color: AppColors.offer,
                          fontSize: 11)),
              ],
            )),
            Row(children: List.generate(5, (i) => Icon(
              i < rating
                  ? Icons.star : Icons.star_border,
              color: AppColors.deal, size: 13))),
          ]),

          if (listingTitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Ανταλλαγή: $listingTitle',
                style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11)),
          ],

          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4)),
          ],

          const SizedBox(height: 8),
          GestureDetector(
            onTap: () =>
                setState(() => _expanded = !_expanded),
            child: Text(
              _expanded
                  ? 'Απόκρυψη σχολίων'
                  : 'Εμφάνιση σχολίων',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12)),
          ),

          if (_expanded) ...[
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('wallPosts')
                  .doc(widget.docId)
                  .collection('comments')
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const SizedBox.shrink();
                }
                return Column(children: [
                  ...snap.data!.docs.map((c) {
                    final d = c.data()
                        as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(
                          top: 6),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          UserAvatar(
                            initials: (d['authorName']
                                    as String? ??
                                '?')[0].toUpperCase(),
                            radius: 10),
                          const SizedBox(width: 6),
                          Expanded(child: Text(
                            '${d['authorName']}: ${d['text']}',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12))),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Σχόλιο...',
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(20),
                          borderSide: BorderSide.none),
                      ),
                    )),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () async {
                        if (_ctrl.text.trim().isEmpty) {
                          return;
                        }
                        await FirebaseFirestore.instance
                            .collection('wallPosts')
                            .doc(widget.docId)
                            .collection('comments')
                            .add({
                          'text':      _ctrl.text.trim(),
                          'authorUid': widget.currentUid,
                          'authorName': 'Εσύ',
                          'createdAt':
                              FieldValue.serverTimestamp(),
                        });
                        _ctrl.clear();
                      },
                      child: Container(
                        width: 32, height: 32,
                        decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle),
                        child: const Icon(
                            Icons.send_rounded,
                            color: AppColors.background,
                            size: 15),
                      ),
                    ),
                  ]),
                ]);
              },
            ),
          ],
        ],
      ),
    );
  }
}