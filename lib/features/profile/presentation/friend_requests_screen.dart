import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/friends_repository.dart';

class FriendRequestsScreen extends ConsumerWidget {
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: Text('inbox.friendRequests'.tr())),
      body: SafeArea(
        top: false,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('friendRequests')
              .where('toUid', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.group_outlined,
                          color: AppColors.textHint, size: 48),
                      const SizedBox(height: 12),
                      Text('freq.noPending'.tr(),
                          style: const TextStyle(
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (context, i) {
                final reqDoc = docs[i];
                final d = reqDoc.data() as Map<String, dynamic>;
                final fromUid = d['fromUid'] as String? ?? '';
                return _RequestTile(
                  requestId: reqDoc.id,
                  fromUid: fromUid,
                  currentUid: uid,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RequestTile extends StatefulWidget {
  final String requestId, fromUid, currentUid;
  const _RequestTile({
    required this.requestId,
    required this.fromUid,
    required this.currentUid,
  });

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await FriendsRepository().accept(
        requestId: widget.requestId,
        fromUid: widget.fromUid,
        toUid: widget.currentUid,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('freq.error'.tr(namedArgs: {'err': '$e'}))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await FriendsRepository().reject(widget.requestId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('freq.error'.tr(namedArgs: {'err': '$e'}))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.fromUid)
          .snapshots(),
      builder: (context, snap) {
        String name = 'common.userFallback'.tr();
        String? avatarUrl;

        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>;
          final first = (d['firstName'] as String?) ?? '';
          final last = (d['lastName'] as String?) ?? '';
          final full = last.isNotEmpty ? '$first $last'.trim() : first.trim();
          if (full.isNotEmpty) name = full;
          avatarUrl = (d['avatarUrl'] as String?) ?? (d['photoUrl'] as String?);
        }

        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

        return ListTile(
          leading: GestureDetector(
            onTap: () => context.push('/profile/${widget.fromUid}'),
            child: UserAvatar(
              initials: initial,
              avatarUrl: avatarUrl,
              radius: 22,
            ),
          ),
          title: Text(name,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          subtitle: Text('freq.wantsToBeFriend'.tr(),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          trailing: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle,
                          color: AppColors.primary, size: 28),
                      onPressed: _accept,
                      tooltip: 'freq.accept'.tr(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined,
                          color: AppColors.danger, size: 26),
                      onPressed: _reject,
                      tooltip: 'freq.reject'.tr(),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
