import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/data/user_repository.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Αποκλεισμένοι χρήστες')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
          }

          final data = snap.data!.data() as Map<String, dynamic>? ?? {};
          final blocked = List<String>.from(data['blockedUids'] ?? []);

          if (blocked.isEmpty) {
            return const Center(
            child: Text('Δεν έχεις αποκλείσει κανέναν.',
                style: TextStyle(color: AppColors.textSecondary)));
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
                    child: const Text('Άρση αποκλεισμού',
                        style: TextStyle(color: AppColors.primary, fontSize: 12)),
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
