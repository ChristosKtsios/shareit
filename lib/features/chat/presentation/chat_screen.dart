import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../profile/data/user_repository.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/error_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../../deals/providers/deal_provider.dart';
import '../../deals/data/deal_model.dart';
import '../../deals/data/deal_repository.dart';
import '../data/chat_repository.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/chat_input_bar.dart';
import '../../../core/widgets/safety_tips.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl = TextEditingController();
  Timer? _typingTimer;
  bool _isTyping = false;
  final _scrollCtrl = ScrollController();

  /// True όταν ο χρήστης έχει ανέβει να διαβάσει παλιότερα μηνύματα.
  /// Τότε (α) εμφανίζεται το κουμπί «κατέβα κάτω» και (β) ΔΕΝ τον τραβάμε
  /// αυτόματα στο τέλος όταν έρθει νέο μήνυμα.
  bool _showJumpToBottom = false;

  /// Πόσα pixels από το τέλος θεωρούμε ότι είναι «στο κάτω μέρος».
  static const _atBottomThreshold = 120.0;

  bool get _isAtBottom {
    if (!_scrollCtrl.hasClients) return true;
    final pos = _scrollCtrl.position;
    return pos.maxScrollExtent - pos.pixels <= _atBottomThreshold;
  }

  void _onScroll() {
    final show = !_isAtBottom;
    if (show != _showJumpToBottom) setState(() => _showJumpToBottom = show);
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollCtrl.hasClients) return;
    final target = _scrollCtrl.position.maxScrollExtent;
    if (animate) {
      _scrollCtrl.animateTo(target,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scrollCtrl.jumpTo(target);
    }
  }
  final _db = FirebaseFirestore.instance;

  Map<String, dynamic>? _chatData;
  String? _otherUid;

  /// UID του τρέχοντος χρήστη, cached ώστε το dispose() να ΜΗΝ χρησιμοποιεί
  /// `ref` (μπορεί να ρίξει αφού το widget αποσυνδεθεί).
  String? _myUid;

  /// Μήνυμα στο οποίο απαντάμε τώρα (null = κανονική αποστολή).
  Map<String, dynamic>? _replyingTo;

  /// Banner ασφαλείας κατά της απάτης — εμφανίζεται μέχρι να το κλείσει ο
  /// χρήστης (μία φορά, όχι σε κάθε συνομιλία).
  bool _showSafety = false;

  @override
  void initState() {
    super.initState();
    _myUid = ref.read(currentUserProvider)?.uid;
    _scrollCtrl.addListener(_onScroll);
    _loadChatData();
    SafetyTips.chatBannerDismissed().then((dismissed) {
      if (mounted && !dismissed) setState(() => _showSafety = true);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    // Καθάρισε το typing flag στο Firestore κατά την έξοδο (χωρίς `ref`).
    final uid = _myUid;
    if (uid != null) {
      ChatRepository()
          .setTyping(chatId: widget.chatId, uid: uid, typing: false);
    }
    super.dispose();
  }

  /// Ενημερώνει το `isTyping` flag (τοπικά + Firestore) ΜΟΝΟ όταν αλλάζει
  /// κατάσταση — αποφεύγει περιττά writes και το «κόλλημα» του δείκτη.
  void _setTyping(bool typing) {
    final uid = _myUid;
    if (uid == null || _isTyping == typing) return;
    _isTyping = typing;
    ChatRepository().setTyping(chatId: widget.chatId, uid: uid, typing: typing);
  }

  void _onTypingChanged(String text) {
    _typingTimer?.cancel();
    // Άδειο πεδίο → σταμάτησε να γράφει αμέσως.
    if (text.trim().isEmpty) {
      _setTyping(false);
      return;
    }
    _setTyping(true);
    // Safety net: auto-clear μετά από ~4 δευτ. αδράνειας.
    _typingTimer = Timer(const Duration(seconds: 4), () => _setTyping(false));
  }

  Future<void> _loadChatData() async {
    try {
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
        ChatRepository().markMessagesRead(
          chatId: widget.chatId,
          currentUid: currentUid,
        );
      }
    } catch (e, s) {
      // Offline / permission / malformed doc — μην αφήσεις το σφάλμα να γίνει
      // unhandled (fatal). Το screen απλώς δεν φορτώνει τα extra δεδομένα.
      logSwallowed(e, s, 'chat _loadChatData');
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    // Στέλνοντας μήνυμα, σταμάτησες να «γράφεις» → καθάρισε το typing flag.
    _typingTimer?.cancel();
    _setTyping(false);
    final replyTo = _replyingTo;
    if (replyTo != null) setState(() => _replyingTo = null);
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    await ChatRepository().send(
      chatId: widget.chatId,
      senderId: uid,
      text: text,
      replyTo: replyTo,
    );
    // Όταν στέλνεις εσύ, πάντα κατεβαίνουμε στο δικό σου μήνυμα.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // μην αγγίζεις τον _scrollCtrl μετά το dispose
      _scrollToBottom();
    });
  }

  /// Διαγραφή δικού μου μηνύματος (soft). Το μήνυμα δεν εξαφανίζεται — μένει
  /// ως «Το μήνυμα διαγράφηκε», ώστε ο συνομιλητής να μη βλέπει τη συνομιλία
  /// να ξαναγράφεται πίσω από την πλάτη του.
  Future<void> _confirmDeleteMessage(String messageId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('msg.deleteTitle'.tr(),
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('msg.deleteBody'.tr(),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr(),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('common.delete'.tr(),
                style: const TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChatRepository().deleteMessage(widget.chatId, messageId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('common.errorGeneric'.tr())),
        );
      }
    }
  }

  /// Dialog επεξεργασίας δικού μου μηνύματος κειμένου.
  Future<void> _editMessage(String messageId, String currentText) async {
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => _EditMessageDialog(initialText: currentText),
    );
    if (newText == null || newText.isEmpty || newText == currentText) return;
    try {
      await ChatRepository().editMessage(
        chatId: widget.chatId,
        messageId: messageId,
        text: newText,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${'common.error'.tr()}: $e')));
      }
    }
  }

  Future<void> _openDealFlow(DealModel? existingDeal) async {
    if (_chatData == null || _otherUid == null) return;

    if (existingDeal == null || existingDeal.status == DealStatus.cancelled) {
      _openNewProposalForm();
      return;
    }
    if (existingDeal.status == DealStatus.completed) {
      final currentUid = ref.read(currentUserProvider)?.uid ?? '';
      try {
        final hasRated = await ref.read(dealRepoProvider).hasUserRated(
              dealId: existingDeal.id,
              userId: currentUid,
            );
        if (!hasRated) {
          if (mounted) {
            await context.push('/rate-deal/${existingDeal.id}');
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
                    title: Text('chatx.blockUserQ'.tr(),
                        style: const TextStyle(color: AppColors.textPrimary)),
                    content: Text('chatx.blockUserBody'.tr(),
                        style: const TextStyle(color: AppColors.textSecondary)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('common.cancel'.tr(),
                              style: const TextStyle(
                                  color: AppColors.textSecondary))),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('chatx.block'.tr(),
                              style: const TextStyle(color: AppColors.danger))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await UserRepository().block(currentUid, _otherUid!);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('chatx.userBlocked'.tr())),
                    );
                    context.pop();
                  }
                }
              } else if (value == 'report') {
                // Κανονική ροή report (targetUid) — την επεξεργάζεται το
                // Cloud Function onReportCreated (counter/auto-hide).
                if (_otherUid != null) {
                  context.push('/report/user/$_otherUid');
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'block',
                child: Row(children: [
                  const Icon(Icons.block, color: AppColors.danger, size: 18),
                  const SizedBox(width: 10),
                  Text('chatx.block'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary)),
                ]),
              ),
              PopupMenuItem(
                value: 'report',
                child: Row(children: [
                  const Icon(Icons.flag_outlined,
                      color: AppColors.deal, size: 18),
                  const SizedBox(width: 10),
                  Text('chatx.report'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_otherUid != null)
          StreamBuilder<DocumentSnapshot>(
            stream: _db.collection('users').doc(currentUid).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || !snap.data!.exists) {
                return const SizedBox.shrink();
              }
              final blocked = List<String>.from((snap.data!.data()
                      as Map<String, dynamic>?)?['blockedUids'] ??
                  []);
              if (!blocked.contains(_otherUid)) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: AppColors.danger.withValues(alpha: 0.15),
                child: Row(children: [
                  const Icon(Icons.block, color: AppColors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'chatx.youBlockedUser'.tr(),
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/settings/blocked'),
                    child: Text('chatx.unblock'.tr(),
                        style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              );
            },
          ),
        dealAsync.when(
          data: (deal) {
            if (deal == null) return const SizedBox.shrink();

            // PENDING — Sender / Receiver UI
            if (deal.status == DealStatus.pending) {
              final isReceiver = deal.proposal1?.userId != currentUid;
              if (!isReceiver) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: AppColors.deal.withValues(alpha: 0.12),
                  child: Row(children: [
                    const Icon(Icons.hourglass_top,
                        color: AppColors.deal, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'chatx.dealSentWaiting'.tr(),
                        style: const TextStyle(
                            color: AppColors.deal,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                );
              }
              // Tap στην κάρτα (όχι στα κουμπιά) → πλήρης οθόνη λεπτομερειών.
              return GestureDetector(
                onTap: () => context.push('/deal-review/${deal.id}'),
                child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: AppColors.deal.withValues(alpha: 0.12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        const Icon(Icons.handshake_outlined,
                            color: AppColors.deal, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('chatx.dealSentToYou'.tr(),
                              style: const TextStyle(
                                  color: AppColors.deal,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const Icon(Icons.chevron_right,
                            color: AppColors.deal, size: 18),
                      ]),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 26),
                        child: Text(deal.proposal1?.details ?? '',
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13)),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await DealRepository().cancel(deal.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'chatx.proposalRejected'.tr())),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('${'common.error'.tr()}: $e')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.close,
                                size: 16, color: AppColors.danger),
                            label: Text('chatx.reject'.tr(),
                                style:
                                    const TextStyle(color: AppColors.danger)),
                            style: OutlinedButton.styleFrom(
                                side:
                                    const BorderSide(color: AppColors.danger)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                await DealRepository().acceptProposal(
                                    dealId: deal.id, userId: currentUid);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('chatx.dealStarted'.tr())),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('${'common.error'.tr()}: $e')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.check, size: 16),
                            label: Text('chatx.accept'.tr()),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.offer,
                                foregroundColor: Colors.white),
                          ),
                        ),
                      ]),
                    ]),
                ),
              );
            }

            // ACTIVE — Countdown banner
            if (deal.status == DealStatus.active) {
              return _ActiveCountdownBanner(deal: deal);
            }

            // COMPLETED — Αξιολόγησε banner
            if (deal.status == DealStatus.completed) {
              final isParticipant =
                  deal.user1Uid == currentUid || deal.user2Uid == currentUid;
              if (!isParticipant) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () => context.push('/rate-deal/${deal.id}'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: AppColors.primary.withValues(alpha: 0.15),
                  child: Row(children: [
                    const Icon(Icons.star_outline,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'chatx.dealDoneRate'.tr(),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.primary, size: 18),
                  ]),
                ),
              );
            }
            return const SizedBox.shrink();
          },
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
              // Χωρίς κλάδο σφάλματος, ένα permission-denied άφηνε τη
              // συνομιλία να γυρίζει spinner ΓΙΑ ΠΑΝΤΑ — ο χρήστης δεν
              // καταλάβαινε ποτέ ότι κάτι πήγε στραβά.
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('common.errorGeneric'.tr(),
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: AppColors.textSecondary)),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary));
              }
              final docs = snap.data!.docs;
              // Auto-scroll ΜΟΝΟ αν ο χρήστης είναι ήδη στο κάτω μέρος.
              //
              // ΠΡΙΝ γινόταν jumpTo σε ΚΑΘΕ ενημέρωση του stream: αν διάβαζες
              // παλιότερα μηνύματα κι έφτανε νέο (ή άλλαζε ένα read receipt),
              // σε πετούσε βίαια στο τέλος και έχανες τη θέση σου.
              final wasAtBottom = _isAtBottom;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return; // μην αγγίζεις τον _scrollCtrl μετά το dispose
                if (wasAtBottom) _scrollToBottom(animate: false);
              });
              if (docs.isEmpty) {
                return Center(
                  child: Text('chatx.startConversation'.tr(),
                      style: const TextStyle(color: AppColors.textHint)),
                );
              }
              return _withJumpToBottom(ListView.builder(
                controller: _scrollCtrl,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final isMe = d['senderId'] == currentUid;
                  final sentAt = (d['sentAt'] as Timestamp?)?.toDate();
                  final messageType = d['messageType'] as String? ?? 'text';
                  final readBy = List<String>.from(d['readBy'] ?? []);
                  final isRead = readBy.any((u) => u != currentUid);
                  final msgText = (d['text'] ?? '') as String;
                  final mId = docs[i].id;
                  final isDeleted = d['isDeleted'] as bool? ?? false;
                  return ChatMessageBubble(
                    text: msgText,
                    isMe: isMe,
                    sentAt: sentAt,
                    chatId: widget.chatId,
                    messageType: messageType,
                    dealData: d['dealData'] as Map<String, dynamic>?,
                    mediaUrl: d['mediaUrl'] as String?,
                    latitude: (d['latitude'] as num?)?.toDouble(),
                    longitude: (d['longitude'] as num?)?.toDouble(),
                    isRead: isRead,
                    messageId: mId,
                    senderId: d['senderId'] as String?,
                    reactions: d['reactions'] as Map<String, dynamic>?,
                    currentUid: currentUid,
                    replyTo: d['replyTo'] as Map<String, dynamic>?,
                    editedAt: (d['editedAt'] as Timestamp?)?.toDate(),
                    // Αντίδραση σε ΚΑΘΕ μήνυμα (δικό μου ή του άλλου) — εκτός από
                    // τα διαγραμμένα. Οι κανόνες το επιτρέπουν: κάθε συμμετέχων
                    // αγγίζει μόνο το ΔΙΚΟ του κλειδί στο reactions.
                    onReact: isDeleted
                        ? null
                        : (emoji) => ChatRepository().setMessageReaction(
                              chatId: widget.chatId,
                              messageId: mId,
                              uid: currentUid,
                              emoji: emoji,
                            ),
                    isDeleted: isDeleted,
                    // Απάντηση: σε κείμενο, φωτογραφίες και βίντεο. (Όχι σε
                    // κάρτες deal ή σε διαγραμμένα μηνύματα.)
                    onReply: (!isDeleted &&
                            (messageType == 'text' ||
                                messageType == 'image' ||
                                messageType == 'video'))
                        ? () => setState(() => _replyingTo = {
                              'messageId': mId,
                              'text': msgText,
                              'senderId': d['senderId'],
                              'messageType': messageType,
                              'mediaUrl': d['mediaUrl'],
                            })
                        : null,
                    // Επεξεργασία: μόνο δικά μου μηνύματα κειμένου.
                    onEdit: (isMe && messageType == 'text' && !isDeleted)
                        ? () => _editMessage(mId, msgText)
                        : null,
                    // Διαγραφή: μόνο δικά μου μηνύματα (κείμενο ή media).
                    onDelete: (isMe && !isDeleted && messageType != 'deal_closed'
                            && messageType != 'deal_proposal')
                        ? () => _confirmDeleteMessage(mId)
                        : null,
                  );
                },
              ));
            },
          ),
        ),
        if (_showSafety)
          SafetyTips.chatBanner(onDismiss: () {
            SafetyTips.dismissChatBanner();
            setState(() => _showSafety = false);
          }),
        if (_replyingTo != null) _buildReplyBanner(),
        SafeArea(
          top: false,
          child: ChatInputBar(
            controller: _msgCtrl,
            onChanged: _onTypingChanged,
            onSend: _sendMessage,
            chatId: widget.chatId,
            replyTo: _replyingTo,
            onMediaSent: () => setState(() => _replyingTo = null),
          ),
        ),
      ]),
    );
  }

  /// Τυλίγει τη λίστα μηνυμάτων και εμφανίζει το κουμπί «κατέβα στα πρόσφατα»
  /// όταν ο χρήστης έχει ανέβει σε παλιότερα μηνύματα.
  Widget _withJumpToBottom(Widget list) {
    return Stack(children: [
      list,
      Positioned(
        right: 12,
        bottom: 12,
        child: AnimatedOpacity(
          opacity: _showJumpToBottom ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          // IgnorePointer όταν είναι αόρατο: αλλιώς θα «έπιανε» πατήματα
          // πάνω από το τελευταίο μήνυμα ενώ δεν φαίνεται.
          child: IgnorePointer(
            ignoring: !_showJumpToBottom,
            child: Material(
              color: AppColors.surface,
              elevation: 4,
              shape: const CircleBorder(
                  side: BorderSide(color: AppColors.border, width: 0.5)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _scrollToBottom,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.keyboard_arrow_down,
                      color: AppColors.textPrimary, size: 26),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildReplyBanner() {
    final preview = (_replyingTo?['text'] as String?)?.trim();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(children: [
        Container(width: 3, height: 34, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('chatx.reply'.tr(),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              Text(
                (preview == null || preview.isEmpty)
                    ? 'chatx.message'.tr()
                    : preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: AppColors.textHint, size: 20),
          onPressed: () => setState(() => _replyingTo = null),
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
      return _staticName(
          _chatData?['otherUserName'] ?? 'chatx.conversation'.tr(),
          listingTitle);
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('users').doc(_otherUid).snapshots(),
      builder: (context, snap) {
        String name = _chatData?['otherUserName'] ?? 'chatx.conversation'.tr();
        String? onlineText;
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>;
          final first = (d['firstName'] as String?) ?? '';
          final last = (d['lastName'] as String?) ?? '';
          final fullName =
              last.isNotEmpty ? '$first $last'.trim() : first.trim();
          if (fullName.isNotEmpty) name = fullName;
          final showOnline = d['showOnlineStatus'] ?? true;
          if (showOnline) {
            final lastSeen = (d['lastSeen'] as Timestamp?)?.toDate();
            if (lastSeen != null) {
              final mins = DateTime.now().difference(lastSeen).inMinutes;
              if (mins < 5) {
                onlineText = 'online';
              } else if (mins < 60) {
                onlineText =
                    'chatx.activeMinsAgo'.tr(namedArgs: {'n': '$mins'});
              } else if (mins < 1440) {
                onlineText = 'chatx.activeHoursAgo'
                    .tr(namedArgs: {'n': '${mins ~/ 60}'});
              } else {
                onlineText = 'chatx.activeDaysAgo'
                    .tr(namedArgs: {'n': '${mins ~/ 1440}'});
              }
            }
          }
        }
        return StreamBuilder<DocumentSnapshot>(
          stream: _db.collection('chats').doc(widget.chatId).snapshots(),
          builder: (context, chatSnap) {
            String? finalText = onlineText;
            if (chatSnap.hasData && chatSnap.data!.exists) {
              final cd = chatSnap.data!.data() as Map<String, dynamic>;
              final typing = List<String>.from(cd['typingUids'] ?? []);
              if (typing.contains(_otherUid)) {
                finalText = 'chatx.typing'.tr();
              }
            }
            return _staticName(name, listingTitle, onlineText: finalText);
          },
        );
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
                color: onlineText == 'online'
                    ? AppColors.success
                    : AppColors.textHint,
                shape: BoxShape.circle,
              ),
            ),
            Text(onlineText,
                style: TextStyle(
                  color: onlineText == 'online'
                      ? AppColors.success
                      : AppColors.textSecondary,
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

/// Dialog επεξεργασίας μηνύματος.
///
/// ΚΡΙΣΙΜΟ — ο TextEditingController ζει ΜΕΣΑ στο dialog, όχι έξω από αυτό.
/// Πριν, ο controller φτιαχνόταν στο `_editMessage` και γινόταν `dispose()` σε
/// `finally`, αμέσως μόλις λυνόταν το future του `showDialog`. Όμως το future
/// λύνεται τη στιγμή του `Navigator.pop` — ΟΧΙ όταν τελειώσει το exit
/// animation. Το TextField ήταν ακόμα ζωντανό και έπεφτε πάνω σε disposed
/// controller κατά το ξεμοντάρισμα· η εξαίρεση έκοβε το unmount στη μέση και
/// άφηνε κρεμασμένους dependents → «'_dependents.isEmpty': is not true».
/// Έτσι, το dispose γίνεται στο State του dialog, δηλαδή αφού φύγει όντως από
/// το δέντρο.
class _EditMessageDialog extends StatefulWidget {
  final String initialText;
  const _EditMessageDialog({required this.initialText});

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('chatx.editMessage'.tr(),
          style: const TextStyle(color: AppColors.textPrimary)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 5,
        minLines: 1,
        maxLength: 2000,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: 'chatx.messageText'.tr()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: Text('common.save'.tr(),
              style: const TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }
}

// ── Active Countdown Banner ──
class _ActiveCountdownBanner extends StatefulWidget {
  final DealModel deal;
  const _ActiveCountdownBanner({required this.deal});

  @override
  State<_ActiveCountdownBanner> createState() => _ActiveCountdownBannerState();
}

class _ActiveCountdownBannerState extends State<_ActiveCountdownBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatCountdown(Duration d) {
    if (d.isNegative) return 'chatx.expired'.tr();
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (days > 0) {
      return 'chatx.cdDHM'
          .tr(namedArgs: {'d': '$days', 'h': '$hours', 'm': '$minutes'});
    }
    if (hours > 0) {
      return 'chatx.cdHMS'
          .tr(namedArgs: {'h': '$hours', 'm': '$minutes', 's': '$seconds'});
    }
    return 'chatx.cdMS'.tr(namedArgs: {'m': '$minutes', 's': '$seconds'});
  }

  @override
  Widget build(BuildContext context) {
    final endDate = widget.deal.endDate;
    final remaining = endDate?.difference(DateTime.now()) ?? Duration.zero;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: AppColors.deal.withValues(alpha: 0.12),
      child: Row(children: [
        const Icon(Icons.timer_outlined, color: AppColors.deal, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'deal.active'.tr(),
            style: const TextStyle(
                color: AppColors.deal,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.deal.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _formatCountdown(remaining),
            style: const TextStyle(
                color: AppColors.deal,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ]),
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
          label = 'chatx.statusActive'.tr();
          icon = Icons.timer_outlined;
          color = AppColors.deal;
          break;
        case DealStatus.completed:
          if (_hasRated == true) {
            label = 'chatx.statusNewDeal'.tr();
            icon = Icons.handshake_outlined;
            color = AppColors.deal;
          } else {
            label = 'chatx.statusRate'.tr();
            icon = Icons.star_outline_rounded;
            color = AppColors.offer;
          }
          break;
        case DealStatus.pending:
        case DealStatus.accepted:
          label = 'chatx.statusPending'.tr();
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
