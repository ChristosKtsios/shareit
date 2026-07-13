import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/data/user_repository.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../core/widgets/empty_state.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid;
    // ΚΡΙΣΙΜΟ: το `?? ''` έριχνε `doc('')` → "document path must be non-empty".
    // Ο currentUserProvider είναι null όσο το auth stream φορτώνει (cold start).
    if (uid == null || uid.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('settings.blockedUsers'.tr())),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const ShimmerList(count: 5);
          }

          final data = snap.data!.data() as Map<String, dynamic>? ?? {};
          final blocked = List<String>.from(data['blockedUids'] ?? []);

          if (blocked.isEmpty) {
            return EmptyState(
              icon: Icons.block,
              title: 'blocked.emptyTitle'.tr(),
              subtitle: 'blocked.emptySubtitle'.tr(),
            );
          }

          return ListView.separated(
            itemCount: blocked.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (_, i) => FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(blocked[i]).get(),
              builder: (_, userSnap) {
                if (!userSnap.hasData) {
                  return const ListTile(
                  leading: CircleAvatar(backgroundColor: AppColors.surfaceVariant),
                  title: Text('...', style: TextStyle(color: AppColors.textHint)),
                );
                }
                final u = userSnap.data!.data() as Map<String, dynamic>? ?? {};
                final name = '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim();
                final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

                return ListTile(
                  leading: UserAvatar(initials: initials),
                  title: Text(name,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  trailing: TextButton(
                    onPressed: () => UserRepository().unblock(uid, blocked[i]),
                    child: Text('blocked.unblock'.tr(),
                        style: const TextStyle(color: AppColors.primary, fontSize: 12)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
