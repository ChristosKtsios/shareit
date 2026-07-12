import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_helpers.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../data/user_post_model.dart';
import '../../data/user_post_repository.dart';

class UserPostCard extends ConsumerStatefulWidget {
  final UserPostModel post;
  const UserPostCard({super.key, required this.post});

  @override
  ConsumerState<UserPostCard> createState() => _UserPostCardState();
}

class _UserPostCardState extends ConsumerState<UserPostCard> {
  bool _liking = false;
  final _commentCtrl = TextEditingController();
  bool _sendingComment = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sendingComment) return;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    setState(() => _sendingComment = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final d = userDoc.data() ?? {};
      final first = d['firstName'] as String? ?? '';
      final last = d['lastName'] as String? ?? '';
      final name = '$first $last'.trim().isEmpty
          ? 'Χρήστης'
          : '$first $last'.trim();
      await UserPostRepository().addComment(
        postId: widget.post.id,
        authorUid: uid,
        authorName: name,
        authorAvatar: d['avatarUrl'] as String?,
        text: text,
      );
      _commentCtrl.clear();
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _toggleLike() async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null || _liking) return;
    setState(() => _liking = true);
    try {
      await UserPostRepository().toggleLike(postId: widget.post.id, userId: uid);
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('userPost.deletePostQ'.tr(),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('userPost.irreversible'.tr(),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('common.delete'.tr(),
                  style: const TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok == true) {
      await UserPostRepository().delete(widget.post.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';
    final isMine = post.authorUid == currentUid;
    final liked = post.isLikedBy(currentUid);

    return InkWell(
      onTap: () => context.push('/user-post/${post.id}'),
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(children: [
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(post.authorUid)
                      .snapshots(),
                  builder: (context, snap) {
                    String name = post.authorName;
                    String? avatar = post.authorAvatar;
                    if (snap.hasData && snap.data!.exists) {
                      final d = snap.data!.data() as Map<String, dynamic>;
                      final first = d['firstName'] as String? ?? '';
                      final last = d['lastName'] as String? ?? '';
                      name = '$first $last'.trim();
                      if (name.isEmpty) name = post.authorName;
                      avatar = (d['avatarUrl'] as String?) ?? avatar;
                    }
                    return Row(children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primary,
                        backgroundImage: avatar != null
                            ? CachedNetworkImageProvider(avatar)
                            : null,
                        child: avatar == null
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    color: AppColors.background,
                                    fontWeight: FontWeight.w700))
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            Text(DateHelpers.timeAgo(post.createdAt),
                                style: const TextStyle(
                                    color: AppColors.textHint, fontSize: 11)),
                          ],
                        ),
                      ),
                    ]);
                  },
                ),
              ),
              // Δικό μου post → διαγραφή. Ξένο post → αναφορά (το Google Play
              // απαιτεί δυνατότητα αναφοράς σε κάθε περιεχόμενο χρήστη).
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz,
                    color: AppColors.textSecondary),
                color: AppColors.surface,
                onSelected: (v) {
                  if (v == 'delete') {
                    _confirmDelete();
                  } else if (v == 'report') {
                    context.push(
                        '/report/post/${post.authorUid}/userPosts/${post.id}');
                  }
                },
                itemBuilder: (_) => [
                  if (isMine)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('common.delete'.tr(),
                          style: const TextStyle(color: AppColors.danger)),
                    )
                  else
                    PopupMenuItem(
                      value: 'report',
                      child: Text('chatx.report'.tr(),
                          style: const TextStyle(color: AppColors.danger)),
                    ),
                ],
              ),
            ]),
          ),
          if (post.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(post.text,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.4)),
            ),
          if (post.hasMedia)
            _MediaGrid(urls: post.mediaUrls, types: post.mediaTypes),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(children: [
              IconButton(
                onPressed: _toggleLike,
                icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? AppColors.danger : AppColors.textSecondary,
                    size: 22),
              ),
              Text('${post.likesCount}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(width: 14),
              IconButton(
                onPressed: () => context.push('/user-post/${post.id}'),
                icon: const Icon(Icons.chat_bubble_outline,
                    color: AppColors.textSecondary, size: 22),
              ),
              Text('${post.commentsCount}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ]),
          ),
          // Inline comment input
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 12),
            child: Row(children: [
              const CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.person,
                    color: AppColors.background, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _commentCtrl,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'userPost.writeCommentShort'.tr(),
                      hintStyle: const TextStyle(
                          color: AppColors.textHint, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (_) => _sendComment(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _sendingComment ? null : _sendComment,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: _sendingComment
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: AppColors.background, strokeWidth: 2))
                      : const Icon(Icons.send_rounded,
                          color: AppColors.background, size: 18),
                ),
              ),
            ]),
          ),
        ],
      ),
    ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  final List<String> urls;
  final List<String> types;
  const _MediaGrid({required this.urls, required this.types});

  // Ασφαλής τύπος: αν το types είναι πιο κοντό από το urls (μερικό/legacy doc)
  // επέστρεψε 'image' αντί να σκάσει RangeError.
  String _typeAt(int i) => i < types.length ? types[i] : 'image';

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    if (urls.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _MediaTile(url: urls[0], type: _typeAt(0), height: 280),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: urls.length,
      itemBuilder: (_, i) =>
          _MediaTile(url: urls[i], type: _typeAt(i), height: 100),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final String url;
  final String type;
  final double height;
  const _MediaTile(
      {required this.url, required this.type, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: type == 'image'
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              height: height,
              width: double.infinity,
              placeholder: (_, __) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2))),
              errorWidget: (_, __, ___) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(Icons.broken_image,
                      color: AppColors.textHint)),
            )
          : _VideoThumb(url: url, height: height),
    );
  }
}

class _VideoThumb extends StatefulWidget {
  final String url;
  final double height;
  const _VideoThumb({required this.url, required this.height});

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ctrl?.value.isInitialized ?? false;
    return Stack(alignment: Alignment.center, children: [
      ready
          ? AspectRatio(
              aspectRatio: _ctrl!.value.aspectRatio,
              child: VideoPlayer(_ctrl!),
            )
          : Container(
              color: AppColors.surfaceVariant,
              height: widget.height,
              width: double.infinity,
            ),
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
      ),
    ]);
  }
}
