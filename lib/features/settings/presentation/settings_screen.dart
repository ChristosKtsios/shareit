import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../../../core/widgets/user_avatar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserDataProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Ρυθμίσεις')),
      body: ListView(children: [
        if (user != null)
          ListTile(
            leading: UserAvatar(initials: user.initials, avatarUrl: user.avatarUrl, showVerified: user.isVerified),
            title: Text(user.fullName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text(user.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            trailing: IconButton(icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                onPressed: () => context.push('/settings/edit-profile')),
          ),
        const Divider(),
        _SettingsTile(icon: Icons.notifications_outlined, label: 'Ειδοποιήσεις',
            onTap: () => context.push('/settings/notifications')),
        _SettingsTile(icon: Icons.bookmark_outline, label: 'Αποθηκευμένες αγγελίες',
            onTap: () => context.push('/saved')),
        _SettingsTile(icon: Icons.lock_outline, label: 'Αλλαγή κωδικού',
            onTap: () => context.push('/settings/change-password')),
        _SettingsTile(icon: Icons.block, label: 'Αποκλεισμένοι χρήστες',
            onTap: () => context.push('/settings/blocked')),
        const Divider(),
        _SettingsTile(icon: Icons.help_outline, label: 'Βοήθεια & Υποστήριξη', onTap: (){}),
        _SettingsTile(icon: Icons.privacy_tip_outlined, label: 'Πολιτική απορρήτου', onTap: (){}),
        const Divider(),
        _SettingsTile(icon: Icons.logout, label: 'Αποσύνδεση', color: AppColors.danger,
            onTap: () => ref.read(authRepoProvider).logout()),
      ]),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap; final Color? color;
  const _SettingsTile({required this.icon,required this.label,required this.onTap,this.color});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color??AppColors.textSecondary, size: 20),
    title: Text(label, style: TextStyle(color: color??AppColors.textPrimary, fontSize: 14)),
    trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 18),
    onTap: onTap,
  );
}
