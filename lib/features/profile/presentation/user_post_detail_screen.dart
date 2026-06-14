import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        authorName: user?.fullName ?? 'Χρήστης',
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
              if (!snap.hasData || !snap.data!.exists) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              final post = UserPostModel.fromFirestore(snap.data!);
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserPostCard(post: post),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Text('Σχόλια',
                          style: TextStyle(
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
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: Text('Δεν υπάρχουν σχόλια ακόμα.',
                                  style: TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 12)),
                            ),
                          );
                        }
                        // Top-level: σχόλια χωρίς parent
                        final topLevel =
                            comments.where((c) => c.parentCommentId == null).toList();
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
                child: Text('Απάντηση στον $_replyToAuthorName',
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
                          ? 'Απάντηση στον $_replyToAuthorName...'
                          : 'Γράψε ένα σχόλιο...',
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
                Container(
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
                      child: const Text('Απάντηση',
                          style: TextStyle(
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
}
