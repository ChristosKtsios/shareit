import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../profile/data/user_repository.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../deals/providers/deal_provider.dart';
import '../../deals/data/deal_model.dart';
import '../data/chat_repository.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_deal_banner.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _db = FirebaseFirestore.instance;

  Map<String, dynamic>? _chatData;
  String? _otherUid;

  @override
  void initState() {
    super.initState();
    _loadChatData();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChatData() async {
    final doc = await _db.collection('chats').doc(widget.chatId).get();
    if (!mounted) return;
    final data = doc.data();
    if (data == null) return;
    final currentUid = ref.read(currentUserProvider)?.uid ?? '';
    final participants = List<String>.from(data['participants'] ?? []);
    final otherUid = participants.firstWhere(
      (p) => p != currentUid,
      orElse: () => '',
    );
    setState(() {
      _chatData = data;
      _otherUid = otherUid.isEmpty ? null : otherUid;
    });
    if (data['unread'] == true) {
      ChatRepository().markRead(widget.chatId);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    await ChatRepository().send(
      chatId: widget.chatId,
      senderId: uid,
      text: text,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openDealFlow(DealModel? existingDeal) async {
    if (_chatData == null || _otherUid == null) return;

    // Καθόλου deal, ή ακυρωμένο → νέα φόρμα πρότασης
    if (existingDeal == null ||
        existingDeal.status == DealStatus.cancelled) {
      _openNewProposalForm();
      return;
    }
    // Completed → έλεγξε αν έχει αξιολογήσει
    if (existingDeal.status == DealStatus.completed) {
      final currentUid = ref.read(currentUserProvider)?.uid ?? '';
      try {
        final hasRated = await ref.read(dealRepoProvider).hasUserRated(
              dealId: existingDeal.id,
              userId: currentUid,
            );
        if (!hasRated) {
          // Αξιολόγησε → μετά την επιστροφή refresh state
          if (mounted) {
            await context.push('/rate-deal/${existingDeal.id}');
            // Trigger rebuild όταν επιστρέψει
            if (mounted) setState(() {});
          }
        } else {
          if (mounted) _openNewProposalForm();
        }
      } catch (_) {
        if (mounted) _openNewProposalForm();
      }
      return;
    }

    // Pending/accepted/active → review screen
    context.push('/deal-review/${existingDeal.id}');
  }

  void _openNewProposalForm() {
    context.push(
      '/deal-proposal/${widget.chatId}'
      '?listingId=${_chatData!['listingId'] ?? ''}'
      '&listingTitle=${Uri.encodeComponent(_chatData!['listingTitle'] ?? '')}'
      '&otherUserUid=$_otherUid',
    );
  }

  void _openOtherProfile() {
    if (_otherUid != null && _otherUid!.isNotEmpty) {
      context.push('/profile/$_otherUid');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';
    final dealAsync = ref.watch(dealByChatProvider(widget.chatId));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: dealAsync.when(
          data: (deal) => _buildTitleRow(deal, currentUid),
          loading: () => _buildTitleRow(null, currentUid),
          error: (_, __) => _buildTitleRow(null, currentUid),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
            color: AppColors.surface,
            onSelected: (value) async {
              if (_otherUid == null) return;
              if (value == 'block') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text('Μπλοκάρισμα χρήστη;',
                        style: TextStyle(color: AppColors.textPrimary)),
                    content: const Text(
                        'Δεν θα μπορείτε να λάβετε μηνύματα από αυτόν τον χρήστη.',
                        style: TextStyle(color: AppColors.textSecondary)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Άκυρο',
                              style: TextStyle(color: AppColors.textSecondary))),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Μπλοκάρισμα',
                              style: TextStyle(color: AppColors.danger))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await UserRepository().block(currentUid, _otherUid!);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ο χρήστης μπλοκαρίστηκε')),
                    );
                    context.pop();
                  }
                }
              } else if (value == 'report') {
                final reason = await showDialog<String>(
                  context: context,
                  builder: (_) => SimpleDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text('Λόγος αναφοράς',
                        style: TextStyle(color: AppColors.textPrimary)),
                    children: [
                      'Spam ή ενοχλητικά μηνύματα',
                      'Απάτη',
                      'Παρενόχληση',
                      'Ακατάλληλο περιεχόμενο',
                      'Άλλο',
                    ]
                        .map((r) => SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, r),
                              child: Text(r,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary)),
                            ))
                        .toList(),
                  ),
                );
                if (reason != null && _otherUid != null) {
                  await FirebaseFirestore.instance
                      .collection('reports')
                      .add({
                    'reporterUid': currentUid,
                    'reportedUid': _otherUid,
                    'reason': reason,
                    'type': 'user',
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Η αναφορά υποβλήθηκε. Ευχαριστούμε!')),
                    );
                  }
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'block',
                child: Row(children: [
                  Icon(Icons.block, color: AppColors.danger, size: 18),
                  SizedBox(width: 10),
                  Text('Μπλοκάρισμα',
                      style: TextStyle(color: AppColors.textPrimary)),
                ]),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Row(children: [
                  Icon(Icons.flag_outlined, color: AppColors.deal, size: 18),
                  SizedBox(width: 10),
                  Text('Αναφορά',
                      style: TextStyle(color: AppColors.textPrimary)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: Column(children: [
        dealAsync.when(
          data: (deal) => deal != null && deal.status == DealStatus.active
              ? ChatDealBanner(deal: deal)
              : const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db
                .collection('chats')
                .doc(widget.chatId)
                .collection('messages')
                .orderBy('sentAt')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary));
              }
              final docs = snap.data!.docs;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollCtrl.hasClients) {
                  _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                }
              });
              if (docs.isEmpty) {
                return const Center(
                  child: Text('Ξεκίνα τη συνομιλία!',
                      style: TextStyle(color: AppColors.textHint)),
                );
              }
              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final isMe = d['senderId'] == currentUid;
                  final sentAt = (d['sentAt'] as Timestamp?)?.toDate();
                  final messageType = d['messageType'] as String? ?? 'text';
                  return ChatMessageBubble(
                    text: d['text'] ?? '',
                    isMe: isMe,
                    sentAt: sentAt,
                    chatId: widget.chatId,
                    messageType: messageType,
                    dealData: d['dealData'] as Map<String, dynamic>?,
                    mediaUrl: d['mediaUrl'] as String?,
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: ChatInputBar(
            controller: _msgCtrl,
            onSend: _sendMessage,
            chatId: widget.chatId,
          ),
        ),
      ]),
    );
  }

  Widget _buildTitleRow(DealModel? deal, String currentUid) {
    final listingTitle = _chatData?['listingTitle'] ?? '';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openOtherProfile,
              child: _buildNameAndListing(listingTitle),
            ),
          ),
          _DealButton(
            deal: deal,
            currentUid: currentUid,
            onTap: () => _openDealFlow(deal),
          ),
        ],
      ),
    );
  }

  Widget _buildNameAndListing(String listingTitle) {
    if (_otherUid == null || _otherUid!.isEmpty) {
      return _staticName(_chatData?['otherUserName'] ?? 'Συνομιλία', listingTitle);
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('users').doc(_otherUid).snapshots(),
      builder: (context, snap) {
        String name = _chatData?['otherUserName'] ?? 'Συνομιλία';
        String? onlineText;
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>;
          final first = (d['firstName'] as String?) ?? '';
          final last = (d['lastName'] as String?) ?? '';
          final fullName = last.isNotEmpty ? '$first $last'.trim() : first.trim();
          if (fullName.isNotEmpty) name = fullName;
          final showOnline = d['showOnlineStatus'] ?? true;
          if (showOnline) {
            final lastSeen = (d['lastSeen'] as Timestamp?)?.toDate();
            if (lastSeen != null) {
              final mins = DateTime.now().difference(lastSeen).inMinutes;
              if (mins < 5) {
                onlineText = 'online';
              } else if (mins < 60) {
                onlineText = 'ενεργός πριν $mins λ.';
              } else if (mins < 1440) {
                onlineText = 'ενεργός πριν ${mins ~/ 60} ώρες';
              } else {
                onlineText = 'ενεργός πριν ${mins ~/ 1440} μέρες';
              }
            }
          }
        }
        return _staticName(name, listingTitle, onlineText: onlineText);
      },
    );
  }

  Widget _staticName(String name, String listingTitle, {String? onlineText}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        if (onlineText != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: onlineText == 'online' ? AppColors.success : AppColors.textHint,
                shape: BoxShape.circle,
              ),
            ),
            Text(onlineText,
                style: TextStyle(
                  color: onlineText == 'online' ? AppColors.success : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
      ],
    );
  }
}

class _DealButton extends ConsumerStatefulWidget {
  final DealModel? deal;
  final String currentUid;
  final VoidCallback onTap;

  const _DealButton({
    required this.deal,
    required this.currentUid,
    required this.onTap,
  });

  @override
  ConsumerState<_DealButton> createState() => _DealButtonState();
}

class _DealButtonState extends ConsumerState<_DealButton> {
  bool? _hasRated;

  @override
  void initState() {
    super.initState();
    _checkRatedStatus();
  }

  @override
  void didUpdateWidget(_DealButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Πάντα ξανά έλεγξε αν αξιολόγησε όταν αλλάζει το deal ή refresh
    _checkRatedStatus();
  }

  Future<void> _checkRatedStatus() async {
    final deal = widget.deal;
    if (deal == null || deal.status != DealStatus.completed) {
      if (mounted) setState(() => _hasRated = null);
      return;
    }
    try {
      final hasRated = await ref.read(dealRepoProvider).hasUserRated(
            dealId: deal.id,
            userId: widget.currentUid,
          );
      if (mounted) setState(() => _hasRated = hasRated);
    } catch (_) {
      if (mounted) setState(() => _hasRated = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deal = widget.deal;
    String label = 'Deal';
    IconData icon = Icons.handshake_outlined;
    Color color = AppColors.deal;

    if (deal != null) {
      switch (deal.status) {
        case DealStatus.active:
          label = 'Ενεργό';
          icon = Icons.timer_outlined;
          color = AppColors.deal;
          break;
        case DealStatus.completed:
          // Αν δεν έχει αξιολογήσει ακόμα → "Αξιολόγησε"
          // Αν έχει αξιολογήσει → "Νέο Deal"
          if (_hasRated == true) {
            label = 'Νέο Deal';
            icon = Icons.handshake_outlined;
            color = AppColors.deal;
          } else {
            label = 'Αξιολόγησε';
            icon = Icons.star_outline_rounded;
            color = AppColors.offer;
          }
          break;
        case DealStatus.pending:
        case DealStatus.accepted:
          label = 'Εκκρεμεί';
          icon = Icons.pending_outlined;
          color = AppColors.deal;
          break;
        case DealStatus.cancelled:
          label = 'Deal';
          icon = Icons.handshake_outlined;
          color = AppColors.deal;
          break;
      }
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
