import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
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
    if (mounted) setState(() => _chatData = doc.data());
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

  void _showDealSheet() {
    if (_chatData == null) return;
    final currentUid = ref.read(currentUserProvider)?.uid ?? '';
    final participants = List<String>.from(_chatData!['participants'] ?? []);
    final otherUid =
        participants.firstWhere((p) => p != currentUid, orElse: () => '');
    context.push(
      '/deal-proposal/${widget.chatId}'
      '?listingId=${_chatData!['listingId'] ?? ''}'
      '&listingTitle=${Uri.encodeComponent(_chatData!['listingTitle'] ?? '')}'
      '&otherUserUid=$otherUid',
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';
    final dealAsync = ref.watch(dealByChatProvider(widget.chatId));
    final chatTitle = _chatData?['otherUserName'] ?? 'Συνομιλία';
    final listingTitle = _chatData?['listingTitle'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chatTitle,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            if (listingTitle.isNotEmpty)
              Text(listingTitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              if (_chatData == null) return;
              final participants =
                  List<String>.from(_chatData!['participants'] ?? []);
              final otherUid = participants.firstWhere((p) => p != currentUid,
                  orElse: () => '');
              if (otherUid.isNotEmpty) {
                context.push('/profile/$otherUid');
              }
            },
          ),
          dealAsync.when(
            data: (deal) => deal == null
                ? TextButton(
                    onPressed: _showDealSheet,
                    child: const Text(AppStrings.dealClose,
                        style: TextStyle(color: AppColors.deal)),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(children: [
        // Deal banner
        dealAsync.when(
          data: (deal) => deal != null && deal.status == DealStatus.active
              ? ChatDealBanner(deal: deal)
              : const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),

        // Messages
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final isMe = d['senderId'] == currentUid;
                  final sentAt = (d['sentAt'] as Timestamp?)?.toDate();
                  return ChatMessageBubble(
                    text: d['text'] ?? '',
                    isMe: isMe,
                    sentAt: sentAt,
                  );
                },
              );
            },
          ),
        ),

        // Input με safe area στο κάτω μέρος
        SafeArea(
          top: false,
          child: ChatInputBar(
            controller: _msgCtrl,
            onSend: _sendMessage,
          ),
        ),
      ]),
    );
  }
}
