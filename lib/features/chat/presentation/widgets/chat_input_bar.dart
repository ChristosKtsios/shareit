import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/services/media_picker_service.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../data/chat_repository.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final String chatId;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.chatId,
  });

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  bool _uploading = false;

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
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα αποστολής: $e')),
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
        // Κουμπί φωτογραφικής μηχανής
        IconButton(
          onPressed: _uploading ? null : _pickAndSend,
          icon: _uploading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary))
              : const Icon(Icons.photo_camera,
                  color: AppColors.primary, size: 24),
        ),
        Expanded(
          child: TextField(
            controller: widget.controller,
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
