import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../auth/providers/auth_provider.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  /// Επιστρέφει το πρώτο γράμμα ασφαλώς, ή '?' αν το string είναι κενό/null
  String _initialFor(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.messages)),
      body: SafeArea(
        top: false,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chats')
              .where('participants', arrayContains: uid)
              .orderBy('lastMessageAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Σφάλμα φόρτωσης συνομιλιών.\n${snap.error}',
                      style: const TextStyle(color: AppColors.textSecondary),
                      textAlign: TextAlign.center),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Δεν υπάρχουν συνομιλίες ακόμα.\n\nΞεκίνα μια συνομιλία στέλνοντας μήνυμα σε μια αγγελία!',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ));
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (context, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                final hasUnread = d['unread'] == true;
                final otherUserName = (d['otherUserName'] as String?)?.trim();
                final displayName =
                    (otherUserName == null || otherUserName.isEmpty)
                        ? 'Χρήστης'
                        : otherUserName;
                final lastMessage = d['lastMessage'] as String? ?? '';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.surfaceVariant,
                    child: Text(
                      _initialFor(otherUserName),
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  title: Text(displayName,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight:
                              hasUnread ? FontWeight.w700 : FontWeight.w500)),
                  subtitle: Text(lastMessage,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: hasUnread
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.primary, shape: BoxShape.circle))
                      : null,
                  onTap: () => context.push('/chat/${docs[i].id}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
