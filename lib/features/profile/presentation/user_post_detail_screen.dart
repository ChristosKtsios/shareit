import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_helpers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/user_post_model.dart';
import '../data/user_post_comment.dart';
import '../data/user_post_repository.dart';
import '../data/user_repository.dart';
import 'widgets/user_post_card.dart';

class UserPostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  const UserPostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<UserPostDetailScreen> createState() =>
      _UserPostDetailScreenState();
}

class _UserPostDetailScreenState extends ConsumerState<UserPostDetailScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  // Reply state
  String? _replyToCommentId;
  String? _replyToAuthorName;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startReply(UserPostComment c) {
    setState(() {
      _replyToCommentId = c.id;
      _replyToAuthorName = c.authorName;
    });
    _focus.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToAuthorName = null;
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;

    setState(() => _sending = true);
    try {
      final user = await UserRepository().get(uid);
      await UserPostRepository().addComment(
        postId: widget.postId,
        authorUid: uid,
        authorName: user?.fullName ?? 'common.userFallback'.tr(),
        authorAvatar: user?.avatarUrl,
        text: text,
        parentCommentId: _replyToCommentId,
        parentAuthorName: _replyToAuthorName,
      );
      _ctrl.clear();
      _cancelReply();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Post')),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('userPosts')
                .doc(widget.postId)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              // Η ανάρτηση διαγράφηκε ή κρύφτηκε από αναφορές. Χωρίς αυτό, ένα
              // deep link (π.χ. από ειδοποίηση) γύριζε ΑΤΕΡΜΟΝΟ spinner.
              if (!snap.data!.exists) {
                return Center(
                  child: Text('userPost.notFound'.tr(),
                      style: const TextStyle(color: AppColors.textSecondary)),
                );
              }
              final post = UserPostModel.fromFirestore(snap.data!);
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserPostCard(post: post),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Text('userPost.comments'.tr(),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
                    StreamBuilder<List<UserPostComment>>(
                      stream: UserPostRepository()
                          .watchComments(widget.postId),
                      builder: (context, csnap) {
                        if (!csnap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: 2)),
                          );
                        }
                        final comments = csnap.data!;
                        if (comments.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Text('userPost.noComments'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 12)),
                            ),
                          );
                        }
                        // Top-level: σχόλια χωρίς parent — ΚΑΙ απαντήσεις των
                        // οποίων ο parent διαγράφηκε (αλλιώς θα «χάνονταν» και
                        // δεν θα ταίριαζε το commentsCount).
                        final ids = comments.map((c) => c.id).toSet();
                        final topLevel = comments
                            .where((c) =>
                                c.parentCommentId == null ||
                                !ids.contains(c.parentCommentId))
                            .toList();
                        return Column(
                          children: topLevel.map((c) {
                            final replies = comments
                                .where((r) => r.parentCommentId == c.id)
                                .toList();
                            return Column(
                              children: [
                                _CommentTile(
                                  comment: c,
                                  postId: post.id,
                                  onReply: () => _startReply(c),
                                ),
                                ...replies.map((r) => Padding(
                                      padding: const EdgeInsets.only(left: 40),
                                      child: _CommentTile(
                                        comment: r,
                                        postId: post.id,
                                        onReply: () => _startReply(c),
                                        isReply: true,
                                      ),
                                    )),
                              ],
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
          ),
        ),
        // Reply banner
        if (_replyToAuthorName != null)
          Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              const Icon(Icons.reply, size: 14, color: AppColors.textHint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'userPost.replyingTo'
                        .tr(namedArgs: {'name': '$_replyToAuthorName'}),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ),
              GestureDetector(
                onTap: _cancelReply,
                child: const Icon(Icons.close,
                    size: 16, color: AppColors.textHint),
              ),
            ]),
          ),
        // Comment input — Instagram style
        SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border:
                  Border(top: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.person, color: AppColors.background, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _replyToCommentId != null
                          ? 'userPost.replyingToHint'
                              .tr(namedArgs: {'name': '$_replyToAuthorName'})
                          : 'userPost.writeComment'.tr(),
                      hintStyle: const TextStyle(
                          color: AppColors.textHint, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _sending ? null : _send,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: AppColors.background, strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            color: AppColors.background, size: 20),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  final UserPostComment comment;
  final String postId;
  final VoidCallback onReply;
  final bool isReply;
  const _CommentTile({
    required this.comment,
    required this.postId,
    required this.onReply,
    this.isReply = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProvider)?.uid;
    final isMine = currentUid == comment.authorUid;
    final liked = currentUid != null && comment.likes.contains(currentUid);

    // ── Διαγραμμένο σχόλιο ──
    // Μένει ορατό ως ένδειξη: οι απαντήσεις σε αυτό δεν κρέμονται στο κενό.
    if (comment.isDeleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          const Icon(Icons.block, size: 14, color: AppColors.textHint),
          const SizedBox(width: 8),
          Text(
            'userPost.commentDeleted'.tr(namedArgs: {'name': comment.authorName}),
            style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12.5,
                fontStyle: FontStyle.italic),
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isReply ? 13 : 16,
            backgroundColor: AppColors.primary,
            backgroundImage: comment.authorAvatar != null
                ? CachedNetworkImageProvider(comment.authorAvatar!)
                : null,
            child: comment.authorAvatar == null
                ? Text(
                    comment.authorName.isNotEmpty
                        ? comment.authorName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: AppColors.background,
                        fontSize: isReply ? 10 : 12,
                        fontWeight: FontWeight.w700))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: () => _showReactionsPicker(context, currentUid),
                  child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(height: 4),
                      Text(comment.text,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              height: 1.3)),
                    ],
                  ),
                ),),
                // Reactions display
                if (comment.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 8),
                    child: Wrap(
                      spacing: 4,
                      children: comment.reactions.entries.map((entry) {
                        final emoji = entry.key;
                        final users = entry.value;
                        if (users.isEmpty) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: currentUid == null
                              ? null
                              : () => UserPostRepository().toggleCommentReaction(
                                    postId: postId,
                                    commentId: comment.id,
                                    uid: currentUid,
                                    emoji: emoji,
                                  ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppColors.border, width: 0.5),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(emoji,
                                  style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 3),
                              Text('${users.length}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 10)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                // Actions row: Like + Reply + count
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8),
                  child: Row(children: [
                    GestureDetector(
                      onTap: currentUid == null
                          ? null
                          : () => UserPostRepository().toggleCommentLike(
                                postId: postId,
                                commentId: comment.id,
                                uid: currentUid,
                                like: !liked,
                              ),
                      child: Row(children: [
                        Icon(
                          liked ? Icons.favorite : Icons.favorite_border,
                          size: 14,
                          color: liked
                              ? AppColors.danger
                              : AppColors.textHint,
                        ),
                        if (comment.likes.isNotEmpty) ...[
                          const SizedBox(width: 3),
                          Text('${comment.likes.length}',
                              style: const TextStyle(
                                  color: AppColors.textHint, fontSize: 11)),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: onReply,
                      child: Text('userPost.reply'.tr(),
                          style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (isMine) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => UserPostRepository()
                            .deleteComment(postId, comment.id),
                        child: const Icon(Icons.delete_outline,
                            size: 14, color: AppColors.textHint),
                      ),
                    ] else ...[
                      const Spacer(),
                      // Αναφορά σχολίου — απαίτηση UGC policy του Play.
                      GestureDetector(
                        onTap: () => context.push(
                            '/report/comment/${comment.authorUid}/userPosts/$postId/${comment.id}'),
                        child: const Icon(Icons.flag_outlined,
                            size: 14, color: AppColors.textHint),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showReactionsPicker(BuildContext ctx, String? uid) {
    if (uid == null) return;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['👍', '❤️', '😂', '😮', '😢', '🔥'].map((e) {
            return GestureDetector(
              onTap: () {
                UserPostRepository().toggleCommentReaction(
                  postId: postId,
                  commentId: comment.id,
                  uid: uid,
                  emoji: e,
                );
                Navigator.pop(ctx);
              },
              child: Text(e, style: const TextStyle(fontSize: 28)),
            );
          }).toList(),
        ),
      ),
    );
  }
}
