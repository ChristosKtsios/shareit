import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../deals/data/deal_model.dart';
import '../../../deals/data/deal_repository.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_helpers.dart';

class ChatMessageBubble extends StatelessWidget {
  void _showMessageOptions(BuildContext ctx, String msgText, bool mine) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.copy, color: AppColors.textSecondary),
          title: const Text('Αντιγραφή',
              style: TextStyle(color: AppColors.textPrimary)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: msgText));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Αντιγράφηκε')),
            );
          },
        ),
        if (!mine)
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: AppColors.deal),
            title: const Text('Αναφορά μηνύματος',
                style: TextStyle(color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Η αναφορά υποβλήθηκε')),
              );
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

  const ChatMessageBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.sentAt,
    this.chatId,
    this.messageType = 'text',
    this.dealData,
    this.mediaUrl,
  });

  @override
  Widget build(BuildContext context) {
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
            child: Text(text,
                style: TextStyle(
                    color: isMe ? AppColors.background : AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4)),
          ),
          if (sentAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Text(
                DateHelpers.timeAgo(sentAt!),
                style: const TextStyle(color: AppColors.textHint, fontSize: 10),
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
  const _ImageBubble({required this.isMe, required this.sentAt, required this.url});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openFullscreen(context, url),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    height: 180,
                    color: AppColors.surfaceVariant,
                    child: const Center(
                        child: CircularProgressIndicator(color: AppColors.primary)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 180,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.broken_image, color: AppColors.textHint),
                  ),
                ),
              ),
            ),
          ),
          if (sentAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Text(DateHelpers.timeAgo(sentAt!),
                  style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
            ),
        ],
      ),
    );
  }

  void _openFullscreen(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
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
  const _VideoBubble({required this.isMe, required this.sentAt, required this.url});

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
        crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openFullscreen(context),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
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
                              child: CircularProgressIndicator(color: AppColors.primary)),
                        ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                  ),
                ]),
              ),
            ),
          ),
          if (widget.sentAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Text(DateHelpers.timeAgo(widget.sentAt!),
                  style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
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
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
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
                          _ctrl.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
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
        const SnackBar(content: Text('Σφάλμα: δεν βρέθηκε chatId')),
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
      final snap = await FirebaseFirestore.instance
          .collection('deals')
          .where('chatId', isEqualTo: chatId)
          .get();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Δεν βρέθηκε deal')),
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
          SnackBar(content: Text('Σφάλμα: $e')),
        );
      }
    }
  }

  void _copyToClipboard(BuildContext context) {
    final title = (data['title'] as String?) ?? '';
    final details = (data['description'] as String?) ?? (data['details'] as String?) ?? '';
    final text = StringBuffer()
      ..writeln('📋 ΠΡΟΤΑΣΗ DEAL')
      ..writeln(title)
      ..writeln('')
      ..writeln(details);
    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Αντιγράφηκε στο πρόχειρο'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?) ?? 'Πρόταση Deal';
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
                  border: Border.all(color: AppColors.deal.withValues(alpha: 0.5), width: 1.5),
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
                        child: const Icon(Icons.swap_horiz_rounded, color: AppColors.deal, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Πρόταση Deal',
                                style: TextStyle(color: AppColors.deal, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                            const SizedBox(height: 2),
                            Text(title,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.deal, size: 22),
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
                    style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
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
      return _btn(isMe ? 'Δες την πρόταση' : 'Άνοιξε για αποδοχή/απόρριψη',
          Icons.visibility, AppColors.deal);
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('deals')
          .doc(dealId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return _btn('Φόρτωση...', Icons.hourglass_empty,
              AppColors.deal.withValues(alpha: 0.6));
        }
        final d = snap.data!.data() as Map<String, dynamic>;
        final statusStr = (d['status'] as String?) ?? 'pending';
        final ratedBy = List<String>.from(d['ratedBy'] ?? []);
        final endDate = (d['endDate'] as Timestamp?)?.toDate();

        if (statusStr == 'pending') {
          return _btn(
              isMe ? 'Δες την πρόταση' : 'Άνοιξε για αποδοχή/απόρριψη',
              Icons.visibility, AppColors.deal);
        }
        if (statusStr == 'accepted' || statusStr == 'active') {
          final rem = endDate?.difference(DateTime.now());
          String t = 'Εκκρεμή';
          if (rem != null && rem.inSeconds > 0) {
            if (rem.inDays > 0) {
              t = 'Εκκρεμή · Λήγει σε ${rem.inDays} μέρες';
            } else if (rem.inHours > 0) {
              t = 'Εκκρεμή · Λήγει σε ${rem.inHours} ώρες';
            } else {
              t = 'Εκκρεμή · Λήγει σε ${rem.inMinutes} λεπτά';
            }
          } else if (rem != null) {
            t = 'Έληξε ο χρόνος';
          }
          return _btn(t, Icons.hourglass_top, AppColors.seek);
        }
        if (statusStr == 'completed' || statusStr == 'cancelled') {
          if (ratedBy.length >= 2) {
            return _btn('Ολοκληρώθηκε', Icons.check_circle, AppColors.success);
          }
          return _btn('⭐ Αξιολόγησε το deal', Icons.star_outline,
              AppColors.primary);
        }
        return _btn('Δες την πρόταση', Icons.visibility, AppColors.deal);
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
