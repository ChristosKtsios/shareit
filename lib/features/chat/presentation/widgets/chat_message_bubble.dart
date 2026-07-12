import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_helpers.dart';

class ChatMessageBubble extends StatelessWidget {
  static const List<String> _reactionEmojis = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏'
  ];

  void _showMessageOptions(BuildContext ctx, String msgText, bool mine) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        // Μπάρα αντιδράσεων — μόνο σε μηνύματα ΑΛΛΟΥ χρήστη (onReact != null).
        if (!mine && onReact != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _reactionEmojis
                  .map((e) => InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          onReact!(e);
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      ))
                  .toList(),
            ),
          ),
        if (!mine && onReact != null) const Divider(height: 1),
        if (onReply != null)
          ListTile(
            leading: const Icon(Icons.reply, color: AppColors.textSecondary),
            title: Text('chatx.reply'.tr(),
                style: TextStyle(color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(ctx);
              onReply!();
            },
          ),
        if (mine && onEdit != null)
          ListTile(
            leading:
                const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
            title: Text('profile.edit'.tr(),
                style: TextStyle(color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(ctx);
              onEdit!();
            },
          ),
        ListTile(
          leading: const Icon(Icons.copy, color: AppColors.textSecondary),
          title: Text('msg.copy'.tr(),
              style: TextStyle(color: AppColors.textPrimary)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: msgText));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text('msg.copied'.tr())),
            );
          },
        ),
        if (!mine && senderId != null && chatId != null && messageId != null)
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: AppColors.deal),
            title: Text('msg.reportMessage'.tr(),
                style: TextStyle(color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(ctx);
              ctx.push('/report/message/$senderId/$chatId/$messageId');
            },
          ),
      ]),
    );
  }

  final String text;
  final bool isMe;
  final DateTime? sentAt;
  final String? chatId;
  final String messageType;
  final Map<String, dynamic>? dealData;
  final String? mediaUrl;
  final int? dealClosedDays;
  final bool isRead;
  final String? messageId;
  final String? senderId;
  final Map<String, dynamic>? reactions;
  final String? currentUid;

  /// Callback αντίδρασης· null → ο χρήστης ΔΕΝ αντιδρά σε αυτό το μήνυμα (π.χ.
  /// στα δικά του). Οι υπάρχουσες αντιδράσεις εμφανίζονται ούτως ή άλλως.
  final void Function(String emoji)? onReact;

  /// Στοιχεία μηνύματος στο οποίο απαντά αυτό (quoted preview): {text, senderId}.
  final Map<String, dynamic>? replyTo;

  /// Πότε επεξεργάστηκε (αν επεξεργάστηκε) — για την ένδειξη «επεξεργασμένο».
  final DateTime? editedAt;

  /// Callback «Απάντηση» σε αυτό το μήνυμα.
  final VoidCallback? onReply;

  /// Callback «Επεξεργασία» — δίνεται μόνο για τα δικά μου μηνύματα κειμένου.
  final VoidCallback? onEdit;

  const ChatMessageBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.sentAt,
    this.chatId,
    this.messageType = 'text',
    this.dealData,
    this.mediaUrl,
    this.dealClosedDays,
    this.isRead = false,
    this.messageId,
    this.senderId,
    this.reactions,
    this.currentUid,
    this.onReact,
    this.replyTo,
    this.editedAt,
    this.onReply,
    this.onEdit,
  });

  /// Quoted preview του μηνύματος στο οποίο απαντά αυτό.
  Widget _buildQuotedReply() {
    final r = replyTo!;
    final preview = (r['text'] as String?)?.trim();
    final onDark = isMe;
    final accent = onDark ? AppColors.background : AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (onDark ? AppColors.background : AppColors.primary)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Text(
        (preview == null || preview.isEmpty) ? 'chatx.message'.tr() : preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: onDark ? AppColors.background : AppColors.textSecondary,
            fontSize: 12,
            height: 1.3),
      ),
    );
  }

  /// Χτίζει τα chips αντιδράσεων (emoji × πλήθος) κάτω από το μήνυμα.
  /// Tap στο chip → toggle της δικής μου αντίδρασης (αν επιτρέπεται).
  Widget? _buildReactions() {
    final r = reactions;
    if (r == null || r.isEmpty) return null;
    final counts = <String, int>{};
    r.forEach((_, emoji) {
      final e = emoji as String;
      counts[e] = (counts[e] ?? 0) + 1;
    });
    final mine = currentUid != null ? r[currentUid] as String? : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(
        spacing: 4,
        children: counts.entries.map((e) {
          final isMine = e.key == mine;
          return GestureDetector(
            onTap: onReact == null ? null : () => onReact!(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isMine
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isMine ? AppColors.primary : AppColors.border,
                    width: 0.5),
              ),
              child: Text('${e.key} ${e.value}',
                  style: const TextStyle(fontSize: 12)),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (messageType == 'deal_closed') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.deal.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'chat.dealClosedFor'.tr(
                namedArgs: {'d': _dealClosedDurationLabel(dealClosedDays)}),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.deal, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    if (messageType == 'deal_proposal' && dealData != null) {
      return _DealCard(
        isMe: isMe,
        sentAt: sentAt,
        data: dealData!,
        chatId: chatId,
      );
    }

    if (messageType == 'image' && mediaUrl != null) {
      return _ImageBubble(
        isMe: isMe,
        sentAt: sentAt,
        url: mediaUrl!,
      );
    }

    if (messageType == 'video' && mediaUrl != null) {
      return _VideoBubble(
        isMe: isMe,
        sentAt: sentAt,
        url: mediaUrl!,
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageOptions(context, text, isMe),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              decoration: BoxDecoration(
                color: isMe ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (replyTo != null) _buildQuotedReply(),
                  Text(text,
                      style: TextStyle(
                          color: isMe
                              ? AppColors.background
                              : AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.4)),
                  if (editedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('msg.edited'.tr(),
                          style: TextStyle(
                              color: (isMe
                                      ? AppColors.background
                                      : AppColors.textHint)
                                  .withValues(alpha: 0.7),
                              fontSize: 10,
                              fontStyle: FontStyle.italic)),
                    ),
                ],
              ),
            ),
            if (_buildReactions() != null) _buildReactions()!,
            if (sentAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                child: Text(
                  DateHelpers.timeAgo(sentAt!),
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── IMAGE BUBBLE ──
class _ImageBubble extends StatelessWidget {
  final bool isMe;
  final DateTime? sentAt;
  final String url;
  const _ImageBubble(
      {required this.isMe, required this.sentAt, required this.url});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openFullscreen(context, url),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    height: 180,
                    color: AppColors.surfaceVariant,
                    child: const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 180,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.broken_image,
                        color: AppColors.textHint),
                  ),
                ),
              ),
            ),
          ),
          if (sentAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Text(DateHelpers.timeAgo(sentAt!),
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 10)),
            ),
        ],
      ),
    );
  }

  void _openFullscreen(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(
          child: InteractiveViewer(
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }
}

// ── VIDEO BUBBLE ──
class _VideoBubble extends StatefulWidget {
  final bool isMe;
  final DateTime? sentAt;
  final String url;
  const _VideoBubble(
      {required this.isMe, required this.sentAt, required this.url});

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  VideoPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _ctrl?.value.isInitialized ?? false;
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openFullscreen(context),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(alignment: Alignment.center, children: [
                  isReady
                      ? AspectRatio(
                          aspectRatio: _ctrl!.value.aspectRatio,
                          child: VideoPlayer(_ctrl!),
                        )
                      : Container(
                          height: 180,
                          color: AppColors.surfaceVariant,
                          child: const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary)),
                        ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 36),
                  ),
                ]),
              ),
            ),
          ),
          if (widget.sentAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Text(DateHelpers.timeAgo(widget.sentAt!),
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 10)),
            ),
        ],
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _VideoFullscreen(url: widget.url),
    ));
  }
}

class _VideoFullscreen extends StatefulWidget {
  final String url;
  const _VideoFullscreen({required this.url});

  @override
  State<_VideoFullscreen> createState() => _VideoFullscreenState();
}

class _VideoFullscreenState extends State<_VideoFullscreen> {
  late VideoPlayerController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _ctrl.play();
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: _ctrl.value.isInitialized
            ? AspectRatio(
                aspectRatio: _ctrl.value.aspectRatio,
                child: Stack(alignment: Alignment.bottomCenter, children: [
                  VideoPlayer(_ctrl),
                  VideoProgressIndicator(_ctrl, allowScrubbing: true),
                  Center(
                    child: IconButton(
                      iconSize: 64,
                      icon: Icon(
                          _ctrl.value.isPlaying
                              ? Icons.pause_circle
                              : Icons.play_circle,
                          color: Colors.white.withValues(alpha: 0.85)),
                      onPressed: () {
                        setState(() {
                          _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
                        });
                      },
                    ),
                  ),
                ]),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

// ── DEAL CARD (unchanged from before) ──
class _DealCard extends StatelessWidget {
  final bool isMe;
  final DateTime? sentAt;
  final Map<String, dynamic> data;
  final String? chatId;

  const _DealCard({
    required this.isMe,
    required this.sentAt,
    required this.data,
    required this.chatId,
  });

  Future<void> _openDeal(BuildContext context) async {
    debugPrint('💼 _openDeal called. chatId=$chatId');
    final embeddedDealId = data['dealId'] as String?;
    if (embeddedDealId != null && embeddedDealId.isNotEmpty) {
      context.push('/deal-review/$embeddedDealId');
      return;
    }

    if (chatId == null || chatId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('msg.errNoChatId'.tr())),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      // Το `participants` φίλτρο είναι απαραίτητο: τα rules επιτρέπουν ανάγνωση
      // deal μόνο στους συμμετέχοντες, και ένα query που δεν το δηλώνει
      // απορρίπτεται ολόκληρο (τα rules δεν φιλτράρουν).
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final snap = await FirebaseFirestore.instance
          .collection('deals')
          .where('chatId', isEqualTo: chatId)
          .where('participants', arrayContains: myUid)
          .get();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('msg.noDeal'.tr())),
        );
        return;
      }

      final sorted = snap.docs.toList()
        ..sort((a, b) {
          final aTs = a.data()['createdAt'] as Timestamp?;
          final bTs = b.data()['createdAt'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return bTs.compareTo(aTs);
        });

      final dealId = sorted.first.id;
      context.push('/deal-review/$dealId');
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'common.error'.tr()}: $e')),
        );
      }
    }
  }

  void _copyToClipboard(BuildContext context) {
    final title = (data['title'] as String?) ?? '';
    final details =
        (data['description'] as String?) ?? (data['details'] as String?) ?? '';
    final text = StringBuffer()
      ..writeln('msg.dealProposalHeader'.tr())
      ..writeln(title)
      ..writeln('')
      ..writeln(details);
    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('msg.copiedClipboard'.tr()),
          duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?) ?? 'msg.dealProposal'.tr();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openDeal(context),
              onLongPress: () => _copyToClipboard(context),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.deal.withValues(alpha: 0.18),
                      AppColors.deal.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.deal.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.deal.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.swap_horiz_rounded,
                            color: AppColors.deal, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('msg.dealProposal'.tr(),
                                style: TextStyle(
                                    color: AppColors.deal,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 2),
                            Text(title,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: AppColors.deal, size: 22),
                    ]),
                    const SizedBox(height: 12),
                    _DealPhaseButton(
                      dealId: data['dealId'] as String?,
                      isMe: isMe,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (sentAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(DateHelpers.timeAgo(sentAt!),
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 10)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── DEAL PHASE BUTTON (3 φάσεις) ──
class _DealPhaseButton extends StatelessWidget {
  final String? dealId;
  final bool isMe;
  const _DealPhaseButton({required this.dealId, required this.isMe});

  @override
  Widget build(BuildContext context) {
    if (dealId == null || dealId!.isEmpty) {
      return _btn(
          isMe ? 'msg.viewProposal'.tr() : 'msg.openToRespond'.tr(),
          Icons.visibility, AppColors.deal);
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('deals')
          .doc(dealId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return _btn('msg.loading'.tr(), Icons.hourglass_empty,
              AppColors.deal.withValues(alpha: 0.6));
        }
        final d = snap.data!.data() as Map<String, dynamic>;
        final statusStr = (d['status'] as String?) ?? 'pending';
        // Το deal θεωρείται πλήρως αξιολογημένο όταν έχουν βαθμολογήσει και οι
        // δύο (ownerRating + seekerRating). Το παλιό 'ratedBy' δεν γράφεται ποτέ.
        final bothRated = d['ownerRating'] != null && d['seekerRating'] != null;
        final endDate = (d['endDate'] as Timestamp?)?.toDate();

        if (statusStr == 'pending') {
          return _btn(
          isMe ? 'msg.viewProposal'.tr() : 'msg.openToRespond'.tr(),
              Icons.visibility, AppColors.deal);
        }
        if (statusStr == 'accepted' || statusStr == 'active') {
          final rem = endDate?.difference(DateTime.now());
          String t = 'msg.pending'.tr();
          if (rem != null && rem.inSeconds > 0) {
            if (rem.inDays > 0) {
              t = 'msg.pendingExpiresDays'.tr(namedArgs: {'n': '${rem.inDays}'});
            } else if (rem.inHours > 0) {
              t = 'msg.pendingExpiresHours'
                  .tr(namedArgs: {'n': '${rem.inHours}'});
            } else {
              t = 'msg.pendingExpiresMins'
                  .tr(namedArgs: {'n': '${rem.inMinutes}'});
            }
          } else if (rem != null) {
            t = 'msg.timeExpired'.tr();
          }
          return _btn(t, Icons.hourglass_top, AppColors.seek);
        }
        if (statusStr == 'completed' || statusStr == 'cancelled') {
          if (bothRated) {
            return _btn('deal.done'.tr(), Icons.check_circle, AppColors.success);
          }
          return _btn(
              'msg.rateDeal'.tr(), Icons.star_outline, AppColors.primary);
        }
        return _btn('msg.viewProposal'.tr(), Icons.visibility, AppColors.deal);
      },
    );
  }

  Widget _btn(String label, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Μεταφρασμένη ετικέτα διάρκειας για το «deal closed» μήνυμα, με βάση τις μέρες.
String _dealClosedDurationLabel(int? days) {
  switch (days) {
    case 1:
      return 'dealsheet.day1'.tr();
    case 3:
      return 'dealsheet.days3'.tr();
    case 7:
      return 'dealsheet.week1'.tr();
    case 14:
      return 'dealsheet.weeks2'.tr();
    default:
      return days != null ? '$days' : '';
  }
}
