import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../../../core/widgets/user_avatar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Αποσύνδεση',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Είσαι σίγουρος ότι θες να αποσυνδεθείς;',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Άκυρο',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Αποσύνδεση',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(authRepoProvider).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserDataProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Ρυθμίσεις')),
      body: ListView(children: [
        if (user != null)
          ListTile(
            leading: UserAvatar(
                initials: user.initials,
                avatarUrl: user.avatarUrl,
                showVerified: user.isVerified),
            title: Text(user.fullName,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text(user.email,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            trailing: IconButton(
                icon: const Icon(Icons.edit_outlined,
                    color: AppColors.textSecondary),
                onPressed: () => context.push('/settings/edit-profile')),
          ),
        const Divider(),

        // ── ΛΟΓΑΡΙΑΣΜΟΣ ──
        const _SectionLabel('Λογαριασμός'),
        _SettingsTile(
            icon: Icons.person_outline,
            label: 'Επεξεργασία προφίλ',
            onTap: () => context.push('/settings/edit-profile')),
        _SettingsTile(
            icon: Icons.lock_outline,
            label: 'Αλλαγή κωδικού',
            onTap: () => context.push('/settings/change-password')),

        const Divider(),

        // ── ΕΦΑΡΜΟΓΗ ──
        const _SectionLabel('Εφαρμογή'),
        _SettingsTile(
            icon: Icons.notifications_outlined,
            label: 'Ειδοποιήσεις',
            onTap: () => context.push('/settings/notifications')),
        _SettingsTile(
            icon: Icons.bookmark_outline,
            label: 'Αποθηκευμένες αγγελίες',
            onTap: () => context.push('/saved')),
        _SettingsTile(
            icon: Icons.block,
            label: 'Αποκλεισμένοι χρήστες',
            onTap: () => context.push('/settings/blocked')),

        const Divider(),

        // ── ΥΠΟΣΤΗΡΙΞΗ ──
        const _SectionLabel('Υποστήριξη'),
        _SettingsTile(
            icon: Icons.help_outline,
            label: 'Βοήθεια & Υποστήριξη',
            onTap: () {}),
        _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Πολιτική Απορρήτου',
            onTap: () => launchUrl(
                Uri.parse('https://shareit-6cfa0.web.app/privacy_policy.html'),
                mode: LaunchMode.externalApplication)),
        _SettingsTile(
            icon: Icons.description_outlined,
            label: 'Όροι Χρήσης',
            onTap: () => launchUrl(
                Uri.parse('https://shareit-6cfa0.web.app/terms.html'),
                mode: LaunchMode.externalApplication)),
        _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Πολιτική απορρήτου',
            onTap: () {}),

        const Divider(),

        // ── ΕΞΟΔΟΣ ──
        _SettingsTile(
            icon: Icons.logout,
            label: 'Αποσύνδεση',
            color: AppColors.danger,
            onTap: () => _confirmLogout(context, ref)),
        _SettingsTile(
            icon: Icons.delete_forever_outlined,
            label: 'Διαγραφή λογαριασμού',
            color: AppColors.danger,
            onTap: () => context.push('/profile/delete')),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5),
        ),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _SettingsTile(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color ?? AppColors.textSecondary, size: 20),
        title: Text(label,
            style:
                TextStyle(color: color ?? AppColors.textPrimary, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right,
            color: AppColors.textHint, size: 18),
        onTap: onTap,
      );
}
