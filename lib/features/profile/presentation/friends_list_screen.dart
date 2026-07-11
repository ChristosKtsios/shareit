import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/friends_repository.dart';

/// Λίστα φίλων του τρέχοντος χρήστη.
/// PRIVACY: Μόνο ο ίδιος ο χρήστης μπορεί να την δει. Αν προσπαθήσει
/// κάποιος άλλος, εμφανίζεται μήνυμα.
class FriendsListScreen extends ConsumerStatefulWidget {
  final String? userId;
  const FriendsListScreen({super.key, this.userId});

  @override
  ConsumerState<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends ConsumerState<FriendsListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';
    final targetUid = widget.userId ?? currentUid;

    // PRIVACY GUARD - μόνο ο ίδιος βλέπει
    if (targetUid != currentUid) {
      return Scaffold(
        appBar: AppBar(title: Text('friends.title'.tr())),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline,
                    color: AppColors.textHint, size: 60),
                const SizedBox(height: 16),
                Text(
                  'friends.private'.tr(),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'friends.privateBody'.tr(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('friends.myFriends'.tr())),
      body: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'friends.searchHint'.tr(),
              prefixIcon: const Icon(Icons.search,
                  color: AppColors.textSecondary, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          color: AppColors.textSecondary, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Friends list
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(currentUid)
                .snapshots(),
            builder: (context, userSnap) {
              if (!userSnap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary));
              }

              final friendIds = List<String>.from((userSnap.data!.data()
                      as Map<String, dynamic>?)?['friends'] ??
                  []);

              if (friendIds.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people_outline,
                            color: AppColors.textHint, size: 60),
                        const SizedBox(height: 12),
                        Text(
                          'friends.noFriends'.tr(),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'friends.noFriendsBody'.tr(),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return _FriendsList(
                friendIds: friendIds,
                query: _query,
                currentUid: currentUid,
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _FriendsList extends StatelessWidget {
  final List<String> friendIds;
  final String query;
  final String currentUid;

  const _FriendsList({
    required this.friendIds,
    required this.query,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    // Firestore whereIn limit = 30. Σε bigger λίστες θα κάνουμε batch.
    final batchIds =
        friendIds.length > 30 ? friendIds.sublist(0, 30) : friendIds;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batchIds)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }

        // Φιλτράρισμα με search query
        final docs = snap.data!.docs.where((doc) {
          if (query.isEmpty) return true;
          final d = doc.data() as Map<String, dynamic>;
          final first = (d['firstName'] as String? ?? '').toLowerCase();
          final last = (d['lastName'] as String? ?? '').toLowerCase();
          // Η αναζήτηση με email καταργήθηκε: τα emails δεν είναι πλέον
          // αναγνώσιμα για άλλους χρήστες (ζουν στο users/{uid}/private/data).
          return first.contains(query) ||
              last.contains(query) ||
              '$first $last'.contains(query);
        }).toList();

        if (docs.isEmpty && query.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off,
                      color: AppColors.textHint, size: 60),
                  const SizedBox(height: 12),
                  Text(
                    'friends.noMatch'.tr(namedArgs: {'q': query}),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: docs.length,
          itemBuilder: (_, i) => _FriendTile(
            doc: docs[i],
            currentUid: currentUid,
          ),
        );
      },
    );
  }
}

class _FriendTile extends StatelessWidget {
  final DocumentSnapshot doc;
  final String currentUid;

  const _FriendTile({required this.doc, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final first = (d['firstName'] as String? ?? '').trim();
    final last = (d['lastName'] as String? ?? '').trim();
    final avatarUrl = (d['avatarUrl'] as String?) ?? (d['photoUrl'] as String?);
    final isVerified = d['isVerified'] as bool? ?? false;
    final rating = (d['rating'] as num?)?.toDouble() ?? 0.0;
    final ratingCount = (d['ratingCount'] as num?)?.toInt() ?? 0;

    String fullName;
    if (first.isNotEmpty && last.isNotEmpty) {
      fullName = '$first $last';
    } else if (first.isNotEmpty) {
      fullName = first;
    } else if (last.isNotEmpty) {
      fullName = last;
    } else {
      fullName = 'Χρήστης';
    }

    String initials;
    if (first.isNotEmpty && last.isNotEmpty) {
      initials = '${first[0]}${last[0]}'.toUpperCase();
    } else if (fullName.isNotEmpty) {
      initials = fullName[0].toUpperCase();
    } else {
      initials = '?';
    }

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: InkWell(
        onTap: () => context.push('/profile/${doc.id}'),
        onLongPress: () => _showRemoveDialog(context, doc.id, fullName),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            UserAvatar(
              initials: initials,
              avatarUrl: avatarUrl,
              radius: 24,
              showVerified: isVerified,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fullName,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  if (ratingCount > 0) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.star, color: AppColors.deal, size: 12),
                      const SizedBox(width: 3),
                      Text('${rating.toStringAsFixed(1)} ($ratingCount)',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ]),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textHint, size: 20),
          ]),
        ),
      ),
    );
  }

  void _showRemoveDialog(BuildContext context, String friendUid, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('friends.removeTitle'.tr(),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('friends.removeBody'.tr(namedArgs: {'name': name}),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.cancel'.tr(),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FriendsRepository().remove(
                currentUid: currentUid,
                targetUid: friendUid,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'friends.removed'.tr(namedArgs: {'name': name}))),
                );
              }
            },
            child: Text('friends.remove'.tr(),
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
