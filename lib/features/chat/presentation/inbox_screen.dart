import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/greek_text.dart';
import '../data/chat_repository.dart';
import '../../report/providers/report_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/friend_requests_banner.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/widgets/empty_state.dart';

/// Μεταφράζει τα app-generated previews (deal/media) που είναι αποθηκευμένα ως
/// σταθερά ελληνικά sentinels στο `lastMessage` του chat doc. Τα κανονικά
/// μηνύματα χρήστη επιστρέφονται ως έχουν.
String _chatPreviewLabel(String m) {
  switch (m) {
    case '📋 Πρόταση Deal':
      return 'inbox.previewDeal'.tr();
    case '📷 Φωτογραφία':
      return 'inbox.previewPhoto'.tr();
    case '🎥 Βίντεο':
      return 'inbox.previewVideo'.tr();
    case '🤝 deal_closed':
      return 'inbox.previewDealClosed'.tr();
    default:
      return m;
  }
}

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  /// Κενό = καμία αναζήτηση → η οθόνη είναι ΑΚΡΙΒΩΣ όπως ήταν.
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
    });
  }

  void _clearQuery() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserProvider)?.uid ?? '';
    final searching = _query.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.messages),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('targetUid', isEqualTo: uid)
                // Το πεδίο λέγεται `isRead` (βλ. NotificationModel). Με `read`
                // το query δεν έβρισκε ΠΟΤΕ κανένα doc → το badge έμενε στο 0.
                .where('isRead', isEqualTo: false)
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
            // ── Αναζήτηση ατόμων (μόνο χρήστες/συνομιλίες) ──
            _InboxSearchField(
              controller: _searchCtrl,
              onChanged: _onQueryChanged,
              onClear: _clearQuery,
              hasQuery: searching,
            ),

            // ── Κουμπί αιτημάτων φιλίας (κρύβεται όσο ψάχνεις) ──
            if (!searching) FriendRequestsBanner(uid: uid),

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
                            'inbox.loadError'
                                .tr(namedArgs: {'err': '${snap.error}'}),
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

                  // Αναζήτηση ατόμων: αντικαθιστά ΜΟΝΟ τη λίστα, το stream μένει ζωντανό.
                  if (searching) {
                    return _PeopleSearchResults(
                      uid: uid,
                      query: _query,
                      chatDocs: docs,
                    );
                  }

                  if (docs.isEmpty) {
                    return EmptyState(
                      icon: Icons.chat_bubble_outline,
                      title: 'inbox.noChats'.tr(),
                      subtitle: 'inbox.noChatsSub'.tr(),
                    );
                  }
                  return RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    onRefresh: () async {
                      await Future.delayed(const Duration(milliseconds: 600));
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, i) {
                        final chatDoc = docs[i];
                        final d = chatDoc.data() as Map<String, dynamic>;
                        // Αδιάβαστο ΜΟΝΟ αν το τελευταίο μήνυμα δεν το έστειλα
                        // εγώ (αλλιώς έβλεπα τα δικά μου chats ως αδιάβαστα).
                        final hasUnread = d['unread'] == true &&
                            (d['lastSenderId'] as String?) != uid;
                        final participants =
                            List<String>.from(d['participants'] ?? []);
                        final otherUid = participants.firstWhere(
                          (p) => p != uid,
                          orElse: () => '',
                        );
                        final lastMessage = _chatPreviewLabel(d['lastMessage'] as String? ?? '');
                        final mutedBy = List<String>.from(d['mutedBy'] ?? []);
                        final isMuted = mutedBy.contains(uid);
                        final fallbackName =
                            (d['otherUserName'] as String?)?.trim() ?? '';

                        return _ChatTile(
                          chatId: chatDoc.id,
                          otherUid: otherUid,
                          fallbackName: fallbackName,
                          lastMessage: lastMessage,
                          hasUnread: hasUnread,
                          isMuted: isMuted,
                        );
                      },
                    ),
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

/// Tile που διαβάζει live το όνομα + avatar του άλλου χρήστη από
/// users/{otherUid} αντί για το static otherUserName του chat doc.
class _ChatTile extends StatelessWidget {
  final String chatId, otherUid, fallbackName, lastMessage;
  final bool hasUnread;
  final bool isMuted;

  const _ChatTile({
    required this.chatId,
    required this.otherUid,
    required this.fallbackName,
    required this.lastMessage,
    required this.hasUnread,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    if (otherUid.isEmpty) {
      return _tile(
          name: fallbackName.isEmpty ? 'common.userFallback'.tr() : fallbackName,
          avatarUrl: null,
          context: context);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(otherUid)
          .snapshots(),
      builder: (context, snap) {
        String name = fallbackName.isEmpty ? 'common.userFallback'.tr() : fallbackName;
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMuted)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.notifications_off,
                  size: 16, color: AppColors.textHint),
            ),
          if (hasUnread)
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle)),
        ],
      ),
      onLongPress: () =>
          _showChatOptions(context, chatId, otherUid, name, isMuted),
      onTap: () => context.push('/chat/$chatId'),
    );
  }

  void _showChatOptions(BuildContext context, String chatId, String otherUid,
      String name, bool isMuted) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Text(name,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 0, color: AppColors.border),
          // Mute
          ListTile(
            leading: Icon(
                isMuted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: AppColors.textSecondary),
            title: Text(
                isMuted ? 'inbox.enableNotif'.tr() : 'inbox.muteNotif'.tr(),
                style: const TextStyle(color: AppColors.textPrimary)),
            onTap: () async {
              Navigator.pop(ctx);
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;
              try {
                await ChatRepository().toggleMute(
                  chatId: chatId,
                  uid: uid,
                  mute: !isMuted,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(isMuted
                            ? 'inbox.notifEnabled'.tr()
                            : 'inbox.chatMuted'.tr())),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${'common.error'.tr()}: $e')),
                  );
                }
              }
            },
          ),
          // Block
          ListTile(
            leading: const Icon(Icons.block, color: AppColors.deal),
            title: Text('inbox.blockUser'.tr(),
                style: const TextStyle(color: AppColors.textPrimary)),
            onTap: () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: Text('inbox.blockQ'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary)),
                  content: Text(
                      'inbox.blockConfirm'.tr(namedArgs: {'name': name}),
                      style: const TextStyle(color: AppColors.textSecondary)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: Text('common.cancel'.tr(),
                            style: const TextStyle(color: AppColors.textSecondary))),
                    TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: Text('inbox.block'.tr(),
                            style: const TextStyle(color: AppColors.danger))),
                  ],
                ),
              );
              if (confirm == true) {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) return;
                try {
                  await blockUser(uid, otherUid);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('inbox.userBlockedName'
                              .tr(namedArgs: {'name': name}))),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${'common.error'.tr()}: $e')),
                    );
                  }
                }
              }
            },
          ),
          // Delete
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.danger),
            title: Text('inbox.deleteChat'.tr(),
                style: const TextStyle(color: AppColors.danger)),
            onTap: () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: Text('inbox.deleteQ'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary)),
                  content: Text('inbox.deleteBody'.tr(),
                      style: const TextStyle(color: AppColors.textSecondary)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: Text('common.cancel'.tr(),
                            style: const TextStyle(color: AppColors.textSecondary))),
                    TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: Text('common.delete'.tr(),
                            style: const TextStyle(color: AppColors.danger))),
                  ],
                ),
              );
              if (confirm == true) {
                try {
                  await ChatRepository().deleteChat(chatId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('inbox.chatDeleted'.tr())),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${'common.error'.tr()}: $e')),
                    );
                  }
                }
              }
            },
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ΑΝΑΖΗΤΗΣΗ ΑΤΟΜΩΝ ΜΕΣΑ ΣΤΑ ΜΗΝΥΜΑΤΑ
// Ξεχωριστή από την κεντρική αναζήτηση (αγγελίες+χρήστες) — ψάχνει ΜΟΝΟ χρήστες.
// ─────────────────────────────────────────────────────────────────────────────

class _InboxSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasQuery;

  const _InboxSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hasQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'inbox.searchHint'.tr(),
          prefixIcon:
              const Icon(Icons.search, color: AppColors.textHint, size: 20),
          suffixIcon: hasQuery
              ? IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textHint, size: 18),
                  onPressed: onClear,
                )
              : null,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Μεταδεδομένα συνομιλίας ανά συνομιλητή (για ranking κατά πρόσφατη επαφή).
class _ChatMeta {
  final String chatId;
  final DateTime? lastMessageAt;
  final String lastMessage;
  const _ChatMeta({
    required this.chatId,
    required this.lastMessageAt,
    required this.lastMessage,
  });
}

class _UserHit {
  final String uid;
  final Map<String, dynamic> data;
  const _UserHit({required this.uid, required this.data});
}

/// Δύο ενότητες: «Συνομιλίες» (ταξινομημένες κατά πιο ΠΡΟΣΦΑΤΗ επικοινωνία,
/// βάσει `lastMessageAt`) και «Προτεινόμενοι» (χρήστες χωρίς συνομιλία μαζί μου).
class _PeopleSearchResults extends StatefulWidget {
  final String uid;
  final String query;
  final List<QueryDocumentSnapshot> chatDocs;

  const _PeopleSearchResults({
    required this.uid,
    required this.query,
    required this.chatDocs,
  });

  @override
  State<_PeopleSearchResults> createState() => _PeopleSearchResultsState();
}

class _PeopleSearchResultsState extends State<_PeopleSearchResults> {
  bool _loading = true;
  final Map<String, Map<String, dynamic>> _partners = {}; // uid -> live user data
  List<String> _myBlocked = const [];
  List<_UserHit> _candidates = const []; // υποψήφιοι για «Προτεινόμενοι»
  String? _startingChatFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PeopleSearchResults old) {
    super.didUpdateWidget(old);
    // Ξαναφόρτωση ΜΟΝΟ αν άλλαξε το σύνολο συνομιλιών — όχι σε κάθε πλήκτρο.
    if (old.chatDocs.length != widget.chatDocs.length) _load();
  }

  /// Χάρτης συνομιλητής -> meta, από τα ΖΩΝΤΑΝΑ chat docs (πάντα φρέσκο).
  Map<String, _ChatMeta> _chatMeta() {
    final map = <String, _ChatMeta>{};
    for (final d in widget.chatDocs) {
      final data = d.data() as Map<String, dynamic>;
      final parts = List<String>.from(data['participants'] ?? []);
      final other = parts.firstWhere((p) => p != widget.uid, orElse: () => '');
      if (other.isEmpty) continue;
      map[other] = _ChatMeta(
        chatId: d.id,
        lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
        lastMessage: _chatPreviewLabel(data['lastMessage'] as String? ?? ''),
      );
    }
    return map;
  }

  Future<void> _load() async {
    final db = FirebaseFirestore.instance;
    try {
      final partnerUids = _chatMeta().keys.toList();

      final myDoc = await db.collection('users').doc(widget.uid).get();
      final blocked = List<String>.from(myDoc.data()?['blockedUids'] ?? []);

      final usersSnap = await db.collection('users').limit(100).get();
      final candidates = usersSnap.docs
          .map((d) => _UserHit(uid: d.id, data: d.data()))
          .toList();

      final partnerDocs = await Future.wait(
        partnerUids.map((u) => db.collection('users').doc(u).get()),
      );

      if (!mounted) return;
      setState(() {
        _myBlocked = blocked;
        _candidates = candidates;
        _partners
          ..clear()
          ..addEntries(partnerDocs
              .where((d) => d.exists)
              .map((d) => MapEntry(d.id, d.data()!)));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matches(Map<String, dynamic> data, String foldedQuery) {
    final first = GreekText.fold((data['firstName'] as String?) ?? '');
    final last = GreekText.fold((data['lastName'] as String?) ?? '');
    final full = '$first $last'.trim();
    return first.contains(foldedQuery) ||
        last.contains(foldedQuery) ||
        full.contains(foldedQuery);
  }

  Future<void> _openChatWith(_UserHit u) async {
    if (_startingChatFor != null) return;
    setState(() => _startingChatFor = u.uid);
    try {
      final first = ((u.data['firstName'] as String?) ?? '').trim();
      final last = ((u.data['lastName'] as String?) ?? '').trim();
      final chatId = await ChatRepository().getOrCreate(
        currentUid: widget.uid,
        otherUid: u.uid,
        listingId: '',
        listingTitle: '',
        otherUserName: '$first $last'.trim(),
      );
      if (!mounted) return;
      context.push('/chat/$chatId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'common.error'.tr()}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingChatFor = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const ShimmerList(count: 6);

    final q = GreekText.fold(widget.query);
    if (q.isEmpty) return const SizedBox.shrink();

    final meta = _chatMeta();

    // ── Ενότητα 1: συνομιλίες — πιο ΠΡΟΣΦΑΤΗ επαφή πρώτα ──
    final conversations = meta.keys
        .where((u) => _partners[u] != null && _matches(_partners[u]!, q))
        .toList()
      ..sort((a, b) {
        final da = meta[a]!.lastMessageAt;
        final dbb = meta[b]!.lastMessageAt;
        if (da == null && dbb == null) return 0;
        if (da == null) return 1;
        if (dbb == null) return -1;
        return dbb.compareTo(da);
      });

    // ── Ενότητα 2: προτεινόμενοι — χωρίς συνομιλία, χωρίς blocked ──
    final suggested = _candidates.where((u) {
      if (u.uid == widget.uid) return false;
      if (meta.containsKey(u.uid)) return false;
      if (_myBlocked.contains(u.uid)) return false;
      final theirBlocked = List<String>.from(u.data['blockedUids'] ?? []);
      if (theirBlocked.contains(widget.uid)) return false;
      return _matches(u.data, q);
    }).toList();

    if (conversations.isEmpty && suggested.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('inbox.noMatches'.tr(),
              style: const TextStyle(color: AppColors.textHint)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (conversations.isNotEmpty) ...[
          _SectionHeader(title: 'inbox.sectionChats'.tr()),
          ...conversations.map((u) => _PersonTile(
                data: _partners[u]!,
                subtitle: meta[u]!.lastMessage,
                onTap: () => context.push('/chat/${meta[u]!.chatId}'),
              )),
        ],
        if (suggested.isNotEmpty) ...[
          _SectionHeader(title: 'inbox.sectionSuggested'.tr()),
          ...suggested.map((u) => _PersonTile(
                data: u.data,
                loading: _startingChatFor == u.uid,
                onTap: () => _openChatWith(u),
              )),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: AppColors.surfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(title,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );
}

class _PersonTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String? subtitle;
  final bool loading;
  final VoidCallback onTap;

  const _PersonTile({
    required this.data,
    this.subtitle,
    this.loading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final first = ((data['firstName'] as String?) ?? '').trim();
    final last = ((data['lastName'] as String?) ?? '').trim();
    final name = '$first $last'.trim();
    final display = name.isEmpty ? 'common.userFallback'.tr() : name;
    final avatar = data['avatarUrl'] as String?;
    final sub = subtitle;

    return ListTile(
      leading: UserAvatar(
        initials: display[0].toUpperCase(),
        avatarUrl: avatar,
        radius: 22,
      ),
      title: Text(display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: (sub == null || sub.isEmpty)
          ? null
          : Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
      trailing: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary))
          : null,
      onTap: loading ? null : onTap,
    );
  }
}
