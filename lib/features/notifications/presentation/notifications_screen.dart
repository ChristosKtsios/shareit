import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_helpers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/notification_model.dart';
import '../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final uid = ref.watch(currentUserProvider)?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ειδοποιήσεις'),
        actions: [
          TextButton(
            onPressed: () => markAllRead(uid),
            child: const Text('Όλα διαβασμένα',
                style: TextStyle(color: AppColors.primary, fontSize: 13)),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const Center(
            child: Text('Σφάλμα φόρτωσης.',
                style: TextStyle(color: AppColors.textSecondary))),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(
              child: Text('Δεν υπάρχουν ειδοποιήσεις.',
                  style: TextStyle(color: AppColors.textSecondary)));
          }
          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (_, i) => _NotificationTile(
              notification: notifications[i],
              onTap: () {
                if (notifications[i].routePath != null) {
                  context.push(notifications[i].routePath!);
                }
              },
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  const _NotificationTile({required this.notification, required this.onTap});

  IconData get _icon {
    switch (notification.type) {
      case NotificationType.newMessage:  return Icons.chat_bubble_outline;
      case NotificationType.dealStarted: return Icons.handshake_outlined;
      case NotificationType.dealExpired: return Icons.check_circle_outline;
      case NotificationType.newRating:   return Icons.star_outline;
      case NotificationType.newComment:  return Icons.comment_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    return ListTile(
      tileColor: isUnread ? AppColors.primary.withValues(alpha: 0.05) : null,
      leading: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(
          color: AppColors.primarySurface,
          shape: BoxShape.circle,
        ),
        child: Icon(_icon, color: AppColors.primary, size: 20),
      ),
      title: Text(notification.title,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
          )),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(notification.body,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 2),
        Text(DateHelpers.timeAgo(notification.createdAt),
            style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
      ]),
      trailing: isUnread
          ? Container(width: 8, height: 8,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle))
          : null,
      onTap: onTap,
    );
  }
}
