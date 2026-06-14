import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_helpers.dart';
import '../../auth/providers/auth_provider.dart';
import '../../deals/providers/deal_provider.dart';
import '../data/wall_post_model.dart';
import '../data/wall_post_repository.dart';

class WallPostDetailScreen extends ConsumerStatefulWidget {
  final String postId;

  const WallPostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<WallPostDetailScreen> createState() =>
      _WallPostDetailScreenState();
}

class _WallPostDetailScreenState extends ConsumerState<WallPostDetailScreen> {
  final _commentCtrl = TextEditingController();
  final _repo = WallPostRepository();
  bool _sending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final currentUid = ref.read(currentUserProvider)?.uid ?? '';
      if (currentUid.isEmpty) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .get();
      String authorName = 'Χρήστης';
      String? authorAvatar;

      if (userDoc.exists) {
        final d = userDoc.data() as Map<String, dynamic>;
        final first = (d['firstName'] as String?) ?? '';
        final last = (d['lastName'] as String?) ?? '';
        authorName = '$first $last'.trim();
        if (authorName.isEmpty) authorName = 'Χρήστης';
        authorAvatar = d['avatarUrl'] as String?;
      }

      await _repo.addComment(
        postId: widget.postId,
        authorUid: currentUid,
        authorName: authorName,
        authorAvatar: authorAvatar,
        text: text,
      );

      _commentCtrl.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatCountdown(Duration d) {
    if (d.isNegative) return 'Έληξε';
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (days > 0) return '${days}μ ${hours}ω ${minutes}λ';
    if (hours > 0) return '${hours}ω ${minutes}λ ${seconds}δ';
    return '${minutes}λ ${seconds}δ';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Deal')),
      body: StreamBuilder<WallPostModel?>(
        stream: _repo.watchById(widget.postId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final post = snap.data;
          if (post == null) {
            return const Center(
                child: Text('Το deal δεν βρέθηκε',
                    style: TextStyle(color: AppColors.textSecondary)));
          }

          final canComment = post.canComment(currentUid);
          final isMyDeal =
              post.user1Uid == currentUid || post.user2Uid == currentUid;
          final statusColor =
              post.isCompleted ? AppColors.primary : AppColors.deal;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    // ── Status + countdown banner ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(
                                  post.isCompleted
                                      ? Icons.check_circle
                                      : Icons.handshake,
                                  color: statusColor,
                                  size: 22),
                              const SizedBox(width: 8),
                              Text(
                                  post.isCompleted
                                      ? 'Ολοκληρωμένο Deal'
                                      : 'Ενεργό Deal',
                                  style: TextStyle(
                                      color: statusColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                            ]),
                            if (post.isActive && post.endDate != null) ...[
                              const SizedBox(height: 12),
                              const Text('Απομένει:',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(
                                _formatCountdown(post.remaining),
                                style: TextStyle(
                                    color: statusColor,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ]),
                              ),
                            ],
                            if (post.isCompleted &&
                                post.completedAt != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Ολοκληρώθηκε στις '
                                '${_formatDateTime(post.completedAt!)}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12),
                              ),
                            ],
                          ]),
                    ),

                    // ── ΑΞΙΟΛΟΓΗΣΕ button (μόνο αν δεν έχει γίνει ήδη) ──
                    if (post.isCompleted &&
                        isMyDeal &&
                        post.dealId != null) ...[
                      const SizedBox(height: 12),
                      _RateButtonOrStatus(
                        dealId: post.dealId!,
                        currentUid: currentUid,
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Συμμετέχοντες ──
                    Row(children: [
                      _UserChip(
                          name: post.user1Name,
                          avatarUrl: post.user1Avatar,
                          uid: post.user1Uid),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.swap_horiz,
                            color: AppColors.textSecondary, size: 18),
                      ),
                      _UserChip(
                          name: post.user2Name,
                          avatarUrl: post.user2Avatar,
                          uid: post.user2Uid),
                    ]),

                    const SizedBox(height: 24),

                    // ── Τίτλος ──
                    Text(post.title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.3)),

                    // ── Λεπτομέρειες ──
                    if (post.details.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(post.details,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                height: 1.5)),
                      ),
                    ],

                    // ── Έναρξη + Λήξη ──
                    if (post.startDate != null || post.endDate != null) ...[
                      const SizedBox(height: 16),
                      if (post.startDate != null)
                        _DateInfoRow(
                          icon: Icons.event_available,
                          label: 'Έναρξη',
                          value: _formatDateTime(post.startDate!),
                        ),
                      if (post.endDate != null) ...[
                        const SizedBox(height: 8),
                        _DateInfoRow(
                          icon: Icons.event_busy,
                          label: 'Λήξη',
                          value: _formatDateTime(post.endDate!),
                          color: AppColors.deal,
                        ),
                      ],
                    ],

                    const SizedBox(height: 28),

                    // ── Comments header ──
                    Row(children: [
                      const Icon(Icons.chat_bubble_outline,
                          color: AppColors.textSecondary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        post.commentsCount == 1
                            ? '1 σχόλιο'
                            : '${post.commentsCount} σχόλια',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),

                    const SizedBox(height: 12),

                    StreamBuilder<List<CommentModel>>(
                      stream: _repo.watchComments(widget.postId),
                      builder: (context, csnap) {
                        if (!csnap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary, strokeWidth: 2),
                            ),
                          );
                        }
                        final comments = csnap.data!;
                        if (comments.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                canComment
                                    ? 'Γίνε ο πρώτος που θα σχολιάσει!'
                                    : 'Δεν υπάρχουν σχόλια ακόμα.',
                                style: const TextStyle(
                                    color: AppColors.textHint, fontSize: 12),
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: comments
                              .map((c) => _CommentTile(
                                    comment: c,
                                    canDelete: c.authorUid == currentUid,
                                    onDelete: () => _repo.deleteComment(
                                      postId: widget.postId,
                                      commentId: c.id,
                                    ),
                                  ))
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── Comment input ──
              if (canComment)
                SafeArea(
                  top: false,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(
                        top: BorderSide(color: AppColors.border, width: 0.5),
                      ),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _commentCtrl,
                          maxLength: 500,
                          maxLines: null,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Γράψε σχόλιο...',
                            counterText: '',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _sending ? null : _sendComment,
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary))
                            : const Icon(Icons.send, color: AppColors.primary),
                      ),
                    ]),
                  ),
                )
              else
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: AppColors.surfaceVariant,
                    child: const Row(children: [
                      Icon(Icons.lock_outline,
                          color: AppColors.textHint, size: 14),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            'Μόνο οι 2 χρήστες του deal και οι φίλοι τους '
                            'μπορούν να σχολιάσουν.',
                            style: TextStyle(
                                color: AppColors.textHint, fontSize: 11)),
                      ),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Smart κουμπί που εμφανίζει:
/// - "Αξιολόγησε" αν δεν έχει αξιολογήσει ο χρήστης
/// - "Έχεις αξιολογήσει ✓" αν έχει ήδη αξιολογήσει
class _RateButtonOrStatus extends ConsumerStatefulWidget {
  final String dealId;
  final String currentUid;
  const _RateButtonOrStatus({
    required this.dealId,
    required this.currentUid,
  });

  @override
  ConsumerState<_RateButtonOrStatus> createState() =>
      _RateButtonOrStatusState();
}

class _RateButtonOrStatusState extends ConsumerState<_RateButtonOrStatus> {
  bool _checking = true;
  bool _hasRated = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final hasRated = await ref.read(dealRepoProvider).hasUserRated(
            dealId: widget.dealId,
            userId: widget.currentUid,
          );
      if (mounted) {
        setState(() {
          _hasRated = hasRated;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const SizedBox(
        height: 46,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2),
          ),
        ),
      );
    }

    if (_hasRated) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.offer.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.offer.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle, color: AppColors.offer, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Έχεις αξιολογήσει αυτό το deal',
                style: TextStyle(
                    color: AppColors.offer,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }

    return ElevatedButton.icon(
      onPressed: () async {
        await context.push('/rate-deal/${widget.dealId}');
        // Μετά την επιστροφή, ξανά έλεγξε αν αξιολογήθηκε
        if (mounted) _check();
      },
      icon: const Icon(Icons.star, size: 18),
      label: const Text('Αξιολόγησε τον άλλο χρήστη',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.offer,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String uid;

  const _UserChip(
      {required this.name, required this.avatarUrl, required this.uid});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Expanded(
      child: GestureDetector(
        onTap: () => context.push('/profile/$uid'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl!) : null,
              child: avatarUrl == null
                  ? Text(initial,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700))
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DateInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _DateInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Row(children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: c, size: 18),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ]);
  }
}

class _CommentTile extends StatelessWidget {
  final CommentModel comment;
  final bool canDelete;
  final VoidCallback onDelete;

  const _CommentTile({
    required this.comment,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // ── Διαγραμμένο σχόλιο ──
    if (comment.isDeleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_off_outlined,
                color: AppColors.textHint, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.3), width: 0.5),
              ),
              child: Row(children: [
                const Icon(Icons.delete_outline,
                    color: AppColors.textHint, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${comment.authorName} διέγραψε το σχόλιό του',
                    style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      );
    }

    // ── Κανονικό σχόλιο ──
    final initial = comment.authorName.isNotEmpty
        ? comment.authorName[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
          backgroundImage: comment.authorAvatar != null
              ? NetworkImage(comment.authorAvatar!)
              : null,
          child: comment.authorAvatar == null
              ? Text(initial,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(comment.authorName,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                Text(DateHelpers.timeAgo(comment.createdAt),
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 10)),
              ]),
              const SizedBox(height: 2),
              Text(comment.text,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13, height: 1.4)),
            ]),
          ),
        ),
        if (canDelete)
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.textHint, size: 16),
            onPressed: () => _confirmDelete(context),
          ),
      ]),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Διαγραφή σχολίου;',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
            'Το σχόλιο θα εμφανίζεται ως διαγραμμένο. Δεν μπορεί να αναιρεθεί.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Άκυρο',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Διαγραφή',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
