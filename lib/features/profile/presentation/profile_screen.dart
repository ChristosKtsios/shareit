import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/friends_repository.dart';
import '../data/wall_post_model.dart';
import '../data/wall_post_repository.dart';
import '../data/user_post_model.dart';
import '../data/user_post_repository.dart';
import 'widgets/user_post_card.dart';
import 'profile_photo_viewer.dart';

class ProfileScreen extends ConsumerWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';
    final targetUid = userId ?? currentUid;
    final isMe = targetUid == currentUid;

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(targetUid)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final data = snap.data!.data() as Map<String, dynamic>? ?? {};
          final firstName = (data['firstName'] as String? ?? '').trim();
          final lastName = (data['lastName'] as String? ?? '').trim();
          final emailFallback = (data['email'] as String? ?? '').trim();
          final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
          final ratingCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
          final dealsCount = (data['dealsCount'] as num?)?.toInt() ?? 0;
          final isVerified = data['isVerified'] as bool? ?? false;
          final avatarUrl =
              (data['avatarUrl'] as String?) ?? (data['photoUrl'] as String?);
          final photos = List<String>.from(data['photos'] ?? []);
          final friends = List<String>.from(data['friends'] ?? []);

          // Fallback logic για το όνομα
          String fullName;
          if (firstName.isNotEmpty && lastName.isNotEmpty) {
            fullName = '$firstName $lastName';
          } else if (firstName.isNotEmpty) {
            fullName = firstName;
          } else if (lastName.isNotEmpty) {
            fullName = lastName;
          } else if (emailFallback.contains('@')) {
            fullName = emailFallback.split('@').first;
          } else {
            fullName = 'Χρήστης';
          }

          // Initials
          String initials;
          if (firstName.isNotEmpty && lastName.isNotEmpty) {
            initials = '${firstName[0]}${lastName[0]}'.toUpperCase();
          } else if (firstName.isNotEmpty) {
            initials = firstName[0].toUpperCase();
          } else if (lastName.isNotEmpty) {
            initials = lastName[0].toUpperCase();
          } else if (fullName.isNotEmpty) {
            initials = fullName[0].toUpperCase();
          } else {
            initials = '?';
          }

          final isFriend = friends.contains(currentUid);

          Future<void> onAvatarTap() async {
            if (photos.isNotEmpty) {
              showProfilePhotoViewer(
                context,
                photos: photos,
                uid: targetUid,
                name: fullName,
                isOwner: isMe,
                currentAvatarUrl: avatarUrl,
              );
            } else if (isMe) {
              final picker = ImagePicker();
              final files = await picker.pickMultiImage(
                  imageQuality: 60, maxWidth: 1200, maxHeight: 1200);
              if (files.isEmpty) return;
              final urls = <String>[];
              for (final f in files) {
                final ref = FirebaseStorage.instance.ref(
                    'users/$targetUid/${DateTime.now().millisecondsSinceEpoch}_${urls.length}.jpg');
                await ref.putFile(File(f.path));
                urls.add(await ref.getDownloadURL());
              }
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(targetUid)
                  .set({'photos': urls, 'avatarUrl': urls.first},
                      SetOptions(merge: true));
            }
          }

          return CustomScrollView(slivers: [
            // ── Header ──
            SliverToBoxAdapter(
                child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 20,
                right: 20,
                bottom: 20,
              ),
              color: AppColors.surface,
              child: Column(children: [
                Row(children: [
                  GestureDetector(
                    onTap: onAvatarTap,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        UserAvatar(
                            initials: initials,
                            avatarUrl: avatarUrl,
                            radius: 36,
                            showVerified: isVerified),
                        if (isMe)
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.surface, width: 2),
                              ),
                              child: const Icon(Icons.add,
                                  color: AppColors.background, size: 14),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fullName,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      _StarRating(rating: rating, count: ratingCount),
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
                          context, ref, targetUid, currentUid, isFriend),
                    ),
                ]),
                if (!isMe && currentUid.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _FriendButton(
                    currentUid: currentUid,
                    targetUid: targetUid,
                  ),
                ],
                const SizedBox(height: 16),

                // ── Stats row (tappable μόνο για τον ίδιο χρήστη) ──
                Row(children: [
                  // Deals — tappable μόνο για mine
                  Expanded(
                    child: _StatBox(
                      label: 'Deals',
                      value: '$dealsCount',
                      icon: Icons.handshake_outlined,
                      color: AppColors.deal,
                      onTap: isMe ? () => context.push('/my-deals') : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Φίλοι — tappable μόνο για mine (privacy)
                  Expanded(
                    child: _StatBox(
                      label: 'Φίλοι',
                      value: '${friends.length}',
                      icon: Icons.people_outline,
                      color: AppColors.primary,
                      onTap: isMe ? () => context.push('/friends') : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Posts — count από userPosts
                  Expanded(
                    child: StreamBuilder<List<UserPostModel>>(
                      stream: UserPostRepository().watchUserPosts(targetUid),
                      builder: (context, snap) {
                        final count = snap.data?.length ?? 0;
                        return _StatBox(
                          label: 'Posts',
                          value: '$count',
                          icon: Icons.article_outlined,
                          color: AppColors.deal,
                          onTap: () => context.push('/user-posts/$targetUid'),
                        );
                      },
                    ),
                  ),
                ]),
              ]),
            )),

            // ── Wall posts ──
            SliverToBoxAdapter(
              child: StreamBuilder<List<WallPostModel>>(
                stream: WallPostRepository().watchUserWallPosts(targetUid),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2),
                      ),
                    );
                  }
                  final posts = snap.data!;
                  if (posts.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text('Δεν υπάρχουν deals ακόμα.',
                            style: TextStyle(
                                color: AppColors.textHint, fontSize: 13)),
                      ),
                    );
                  }
                  final active = posts.where((p) => p.isActive).toList();
                  final completed = posts.where((p) => p.isCompleted).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (active.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: Text('Ενεργά Deal',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                        ...active.map((p) => _WallPostCard(post: p)),
                      ],
                      if (completed.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: Text('Ολοκληρωμένα Deal',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                        ...completed.map((p) => _WallPostCard(post: p)),
                      ],
                      const SizedBox(height: 32),
                    ],
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref, String targetUid,
      String currentUid, bool isFriend) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFriend)
            ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: AppColors.textSecondary),
              title: const Text('Αφαίρεση φίλου',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                FriendsRepository()
                    .remove(currentUid: currentUid, targetUid: targetUid);
              },
            ),
          ListTile(
            leading: const Icon(Icons.block, color: AppColors.danger),
            title: const Text('Αποκλεισμός',
                style: TextStyle(color: AppColors.danger)),
            onTap: () {
              Navigator.pop(context);
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUid)
                  .update({
                'blockedUids': FieldValue.arrayUnion([targetUid]),
              });
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.flag_outlined, color: AppColors.textSecondary),
            title: const Text('Αναφορά',
                style: TextStyle(color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              context.push('/report/user/$targetUid');
            },
          ),
        ],
      ),
    );
  }
}

// ── Wall Post Card (με countdown) ──
class _WallPostCard extends StatefulWidget {
  final WallPostModel post;
  const _WallPostCard({required this.post});
  @override
  State<_WallPostCard> createState() => _WallPostCardState();
}

class _WallPostCardState extends State<_WallPostCard> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    if (widget.post.isActive && !widget.post.hasExpired) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isCompleted = post.isCompleted;
    final statusColor = isCompleted ? AppColors.primary : AppColors.deal;
    return InkWell(
      onTap: () => context.push('/wall-post/${post.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: statusColor.withValues(alpha: 0.4), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle_outline
                      : Icons.handshake_outlined,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCompleted ? 'Ολοκληρωμένο Deal' : 'Ενεργό Deal',
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5),
                    ),
                    Text(
                      '${post.user1Name} & ${post.user2Name}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isCompleted && post.completedAt != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDate(post.completedAt!),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                )
              else if (post.endDate != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatCountdown(post.remaining),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Text(post.title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            if (post.details.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                post.details,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.chat_bubble_outline,
                  size: 14, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(
                post.commentsCount == 1
                    ? '1 σχόλιο'
                    : '${post.commentsCount} σχόλια',
                style: const TextStyle(color: AppColors.textHint, fontSize: 11),
              ),
              const Spacer(),
              Text('Άνοιξε',
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: statusColor, size: 16),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Friend Button ──
class _FriendButton extends StatefulWidget {
  final String currentUid, targetUid;
  const _FriendButton({required this.currentUid, required this.targetUid});
  @override
  State<_FriendButton> createState() => _FriendButtonState();
}

class _FriendButtonState extends State<_FriendButton> {
  bool _busy = false;
  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await FriendsRepository().sendRequest(
        fromUid: widget.currentUid,
        toUid: widget.targetUid,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptFromHere() async {
    setState(() => _busy = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('friendRequests')
          .where('fromUid', isEqualTo: widget.targetUid)
          .where('toUid', isEqualTo: widget.currentUid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        await FriendsRepository().accept(
          requestId: snap.docs.first.id,
          fromUid: widget.targetUid,
          toUid: widget.currentUid,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: FriendsRepository().friendshipStatus(
        currentUid: widget.currentUid,
        targetUid: widget.targetUid,
      ),
      builder: (context, snap) {
        final status = snap.data ?? 'none';
        if (_busy) {
          return const SizedBox(
            height: 38,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              ),
            ),
          );
        }
        switch (status) {
          case 'friends':
            return _btn(
              label: '✓ Φίλοι',
              icon: Icons.check,
              outlined: true,
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: AppColors.surface,
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Είστε φίλοι',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ),
                      ListTile(
                        leading: const Icon(Icons.person_remove_outlined,
                            color: AppColors.danger),
                        title: const Text('Αφαίρεση φίλου',
                            style: TextStyle(color: AppColors.danger)),
                        onTap: () async {
                          Navigator.pop(context);
                          setState(() => _busy = true);
                          try {
                            await FriendsRepository().remove(
                              currentUid: widget.currentUid,
                              targetUid: widget.targetUid,
                            );
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                    ]),
                  ),
                );
              },
            );
          case 'sent':
            return _btn(
              label: 'Αναμονή',
              icon: Icons.hourglass_top_outlined,
              outlined: true,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Το αίτημα στάλθηκε. Περιμένει αποδοχή.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            );
          case 'received':
            return Row(
              children: [
                Expanded(
                  child: _btn(
                    label: 'Αποδοχή',
                    icon: Icons.check_circle_outline,
                    outlined: false,
                    onTap: _acceptFromHere,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _btn(
                    label: 'Δες αίτημα',
                    icon: Icons.group_add,
                    outlined: true,
                    onTap: () => context.push('/friend-requests'),
                  ),
                ),
              ],
            );
          case 'none':
          default:
            return _btn(
              label: 'Προσθήκη φίλου',
              icon: Icons.person_add_alt_1,
              outlined: false,
              onTap: _send,
            );
        }
      },
    );
  }

  Widget _btn({
    required String label,
    required IconData icon,
    required bool outlined,
    required VoidCallback onTap,
  }) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: AppColors.primary),
        label: Text(label,
            style: const TextStyle(
                color: AppColors.primary, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(38),
          side: const BorderSide(color: AppColors.primary),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: AppColors.background),
      label: Text(label,
          style: const TextStyle(
              color: AppColors.background, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ── Stats Box (πλέον δέχεται onTap για να γίνεται tappable) ──
class _StatBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
      ]),
    );

    // Αν δεν έχει onTap, γυρνάει απλό container (μη-tappable)
    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}

// ── Star Rating ──
class _StarRating extends StatelessWidget {
  final double rating;
  final int count;
  const _StarRating({required this.rating, required this.count});

  @override
  Widget build(BuildContext context) => Row(children: [
        ...List.generate(
            5,
            (i) => Icon(
                i < rating.floor()
                    ? Icons.star
                    : (i < rating ? Icons.star_half : Icons.star_border),
                color: AppColors.deal,
                size: 16)),
        const SizedBox(width: 4),
        Text('${rating.toStringAsFixed(1)} ($count)',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ]);
}
