import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/media_picker_service.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../data/chat_repository.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String>? onChanged;
  final String chatId;

  /// Το μήνυμα στο οποίο απαντάμε — ισχύει και για φωτογραφίες/βίντεο, ώστε να
  /// μπορείς να απαντήσεις **με** media σε ένα μήνυμα.
  final Map<String, dynamic>? replyTo;

  /// Καλείται αφού σταλεί media, ώστε η οθόνη να καθαρίσει το reply banner.
  final VoidCallback? onMediaSent;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onChanged,
    required this.chatId,
    this.replyTo,
    this.onMediaSent,
  });

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  bool _uploading = false;

  /// Μενού συνημμένων (στυλ Signal): ανοίγει με ωραίο bottom sheet και δίνει
  /// τις επιλογές «Φωτογραφία/Βίντεο» και «Τοποθεσία».
  Future<void> _showAttachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 6),
          _AttachOption(
            icon: Icons.photo_library_outlined,
            color: AppColors.seek,
            label: 'chatx.attachPhoto'.tr(),
            onTap: () => Navigator.pop(ctx, 'media'),
          ),
          _AttachOption(
            icon: Icons.location_on_outlined,
            color: AppColors.offer,
            label: 'chatx.attachLocation'.tr(),
            onTap: () => Navigator.pop(ctx, 'location'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == 'media') {
      await _pickAndSend();
    } else if (choice == 'location') {
      await _sendLocation();
    }
  }

  Future<void> _sendLocation() async {
    setState(() => _uploading = true);
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('chatx.locationFailed'.tr())),
          );
        }
        return;
      }
      final uid = ref.read(currentUserProvider)?.uid ?? '';
      await ChatRepository().sendLocationMessage(
        chatId: widget.chatId,
        senderId: uid,
        latitude: pos.latitude,
        longitude: pos.longitude,
        replyTo: widget.replyTo,
      );
      widget.onMediaSent?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'msg.sendError'.tr()}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickAndSend() async {
    final picker = MediaPickerService();
    final media = await picker.showPickerSheet(context);
    if (media == null) return;

    setState(() => _uploading = true);
    try {
      final uid = ref.read(currentUserProvider)?.uid ?? '';
      final url = await picker.uploadToStorage(
        file: media.file,
        folder: 'chats/${widget.chatId}',
        type: media.type,
      );
      await ChatRepository().sendMediaMessage(
        chatId: widget.chatId,
        senderId: uid,
        mediaUrl: url,
        mediaType: media.type == MediaType.image ? 'image' : 'video',
        replyTo: widget.replyTo,
      );
      widget.onMediaSent?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'msg.sendError'.tr()}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
        top: 8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(children: [
        // Κουμπί «+» → μενού συνημμένων (φωτο/βίντεο + τοποθεσία)
        IconButton(
          onPressed: _uploading ? null : _showAttachMenu,
          icon: _uploading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary))
              : const Icon(Icons.add_circle_outline,
                  color: AppColors.primary, size: 26),
        ),
        Expanded(
          child: TextField(
            controller: widget.controller,
            onChanged: widget.onChanged,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: AppStrings.typeMessage,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: widget.onSend,
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded,
                color: AppColors.background, size: 18),
          ),
        ),
      ]),
    );
  }
}

/// Μία γραμμή-επιλογή στο μενού συνημμένων (εικονίδιο σε χρωματιστό κύκλο +
/// ετικέτα), στυλ Signal.
class _AttachOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _AttachOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}
