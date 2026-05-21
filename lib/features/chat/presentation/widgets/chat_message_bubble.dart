import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_helpers.dart';

class ChatMessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final DateTime? sentAt;

  const ChatMessageBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.sentAt,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.only(
                topLeft:     const Radius.circular(16),
                topRight:    const Radius.circular(16),
                bottomLeft:  Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
            ),
            child: Text(text,
                style: TextStyle(
                    color: isMe
                        ? AppColors.background : AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4)),
          ),
          if (sentAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Text(
                DateHelpers.timeAgo(sentAt!),
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}