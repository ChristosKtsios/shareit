import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
        top: 8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
            top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14),
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: AppStrings.typeMessage,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
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
          onTap: onSend,
          child: Container(
            width: 42, height: 42,
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