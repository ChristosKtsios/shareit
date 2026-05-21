import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';

class WallPostDetailScreen extends ConsumerWidget {
  final String postId;
  const WallPostDetailScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';
    final commentCtrl = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Αξιολόγηση')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('wallPosts').doc(postId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
          }
          final d = snap.data!.data() as Map<String, dynamic>? ?? {};
          final authorName   = d['authorName']   as String? ?? '';
          final text         = d['text']         as String? ?? '';
          final rating       = (d['rating']      as num?)?.toDouble() ?? 0.0;
          final listingTitle = d['listingTitle'] as String? ?? '';

          return Column(children: [
            // Post
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.surface,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  UserAvatar(initials: authorName.isNotEmpty ? authorName[0].toUpperCase() : '?', radius: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(authorName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    Text('Ανταλλαγή: $listingTitle', style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                  ])),
                  Row(children: List.generate(5, (i) => Icon(
                    i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: AppColors.deal, size: 16))),
                ]),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
                ],
              ]),
            ),
            const Divider(height: 0),

            // Comments
            Expanded(child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('wallPosts').doc(postId).collection('comments')
                  .orderBy('createdAt').snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                  child: Text('Δεν υπάρχουν σχόλια ακόμα.',
                      style: TextStyle(color: AppColors.textHint)));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final c = docs[i].data() as Map<String, dynamic>;
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      UserAvatar(
                        initials: (c['authorName'] as String? ?? '?')[0].toUpperCase(),
                        radius: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['authorName'] ?? '', style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(c['text'] ?? '', style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                      ])),
                    ]);
                  },
                );
              },
            )),

            // Input
            Container(
              padding: EdgeInsets.only(
                left: 12, right: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                top: 8,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Row(children: [
                Expanded(child: TextField(
                  controller: commentCtrl,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Γράψε σχόλιο...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true, fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                )),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    if (commentCtrl.text.trim().isEmpty) return;
                    await FirebaseFirestore.instance
                        .collection('wallPosts').doc(postId).collection('comments').add({
                      'text': commentCtrl.text.trim(),
                      'authorUid': currentUid,
                      'authorName': 'Εσύ',
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    commentCtrl.clear();
                  },
                  child: Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded, color: AppColors.background, size: 18),
                  ),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
