import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/chat_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/widgets/empty_state.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.messages),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('targetUid', isEqualTo: uid)
                .where('read', isEqualTo: false)
                .snapshots(),
            builder: (context, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Stack(children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined,
                      color: AppColors.textPrimary),
                  onPressed: () => context.push('/notifications'),
                ),
                if (count > 0)
                  Positioned(
                    top: 8,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── Κουμπί αιτημάτων φιλίας ──
            _FriendRequestsBanner(uid: uid),

            // ── Λίστα chats ──
            Expanded(
              child: StreamBuilder<List<QueryDocumentSnapshot>>(
                stream: ChatRepository().inboxStreamFiltered(uid),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                            'Σφάλμα φόρτωσης συνομιλιών.\n${snap.error}',
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                            textAlign: TextAlign.center),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const ShimmerList(count: 6);
                  }
                  final docs = snap.data!;
                  if (docs.isEmpty) {
                    return const EmptyState(
                      icon: Icons.chat_bubble_outline,
                      title: 'Δεν υπάρχουν συνομιλίες ακόμα',
                      subtitle: 'Ξεκίνα μια συνομιλία στέλνοντας μήνυμα σε μια αγγελία!',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (context, i) {
                      final chatDoc = docs[i];
                      final d = chatDoc.data() as Map<String, dynamic>;
                      final hasUnread = d['unread'] == true;
                      final participants =
                          List<String>.from(d['participants'] ?? []);
                      final otherUid = participants.firstWhere(
                        (p) => p != uid,
                        orElse: () => '',
                      );
                      final lastMessage = d['lastMessage'] as String? ?? '';
                      final fallbackName =
                          (d['otherUserName'] as String?)?.trim() ?? '';

                      return _ChatTile(
                        chatId: chatDoc.id,
                        otherUid: otherUid,
                        fallbackName: fallbackName,
                        lastMessage: lastMessage,
                        hasUnread: hasUnread,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner με αιτήματα φιλίας. Εμφανίζεται μόνο όταν υπάρχει
/// τουλάχιστον ένα pending request προς τον τρέχοντα χρήστη.
class _FriendRequestsBanner extends StatelessWidget {
  final String uid;
  const _FriendRequestsBanner({required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friendRequests')
          .where('toUid', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final count = snap.data!.docs.length;

        return InkWell(
          onTap: () => context.push('/friend-requests'),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.group_add,
                      color: AppColors.background, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Αιτήματα φιλίας',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      Text(count == 1 ? '1 νέο αίτημα' : '$count νέα αιτήματα',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tile που διαβάζει live το όνομα + avatar του άλλου χρήστη από
/// users/{otherUid} αντί για το static otherUserName του chat doc.
class _ChatTile extends StatelessWidget {
  final String chatId, otherUid, fallbackName, lastMessage;
  final bool hasUnread;

  const _ChatTile({
    required this.chatId,
    required this.otherUid,
    required this.fallbackName,
    required this.lastMessage,
    required this.hasUnread,
  });

  @override
  Widget build(BuildContext context) {
    if (otherUid.isEmpty) {
      return _tile(
          name: fallbackName.isEmpty ? 'Χρήστης' : fallbackName,
          avatarUrl: null,
          context: context);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(otherUid)
          .snapshots(),
      builder: (context, snap) {
        String name = fallbackName.isEmpty ? 'Χρήστης' : fallbackName;
        String? avatarUrl;

        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>;
          final first = (d['firstName'] as String?) ?? '';
          final last = (d['lastName'] as String?) ?? '';
          final fullName =
              last.isNotEmpty ? '$first $last'.trim() : first.trim();
          if (fullName.isNotEmpty) name = fullName;
          avatarUrl = (d['avatarUrl'] as String?) ?? (d['photoUrl'] as String?);
        }

        return _tile(name: name, avatarUrl: avatarUrl, context: context);
      },
    );
  }

  Widget _tile({
    required String name,
    required String? avatarUrl,
    required BuildContext context,
  }) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return ListTile(
      leading: UserAvatar(
        initials: initial,
        avatarUrl: avatarUrl,
        radius: 22,
      ),
      title: Text(name,
          style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500)),
      subtitle: Text(lastMessage,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: hasUnread
          ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle))
          : null,
      onTap: () => context.push('/chat/$chatId'),
    );
  }
}
