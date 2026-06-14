import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../data/user_post_model.dart';
import '../data/user_post_repository.dart';
import '../../auth/providers/auth_provider.dart';
import 'widgets/user_post_card.dart';

class UserPostsScreen extends ConsumerWidget {
  final String uid;
  const UserPostsScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProvider)?.uid;
    final isMe = currentUid == uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: isMe
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              onPressed: () => context.push('/create-post'),
              icon: const Icon(Icons.add),
              label: const Text('Νέο Post',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, snap) {
            String name = 'Posts';
            if (snap.hasData && snap.data!.exists) {
              final d = snap.data!.data() as Map<String, dynamic>;
              final first = d['firstName'] ?? '';
              name = first.isNotEmpty ? 'Posts του $first' : 'Posts';
            }
            return Text(name);
          },
        ),
      ),
      body: StreamBuilder<List<UserPostModel>>(
        stream: UserPostRepository().watchUserPosts(uid),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          final posts = snap.data!;
          if (posts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.article_outlined,
                        size: 64, color: AppColors.textHint),
                    SizedBox(height: 16),
                    Text('Δεν υπάρχουν posts ακόμα',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 14)),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: posts.length,
            itemBuilder: (_, i) => UserPostCard(post: posts[i]),
          );
        },
      ),
    );
  }
}
