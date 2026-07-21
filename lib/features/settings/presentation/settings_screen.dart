import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/legal_urls.dart';
import '../../../core/services/fcm_service.dart';
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
        title: Text('settings.logoutConfirmTitle'.tr(),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('settings.logoutConfirmBody'.tr(),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr(),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('settings.logout'.tr(),
                style: const TextStyle(color: AppColors.danger)),
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
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: ListView(children: [
        if (user != null)
          ListTile(
            leading: UserAvatar(
                initials: user.initials,
                avatarUrl: user.avatarUrl,
                showVerified: user.phoneVerified),
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
        _SectionLabel('settings.account'.tr()),
        _SettingsTile(
            icon: Icons.person_outline,
            label: 'settings.editProfile'.tr(),
            onTap: () => context.push('/settings/edit-profile')),
        _SettingsTile(
            icon: Icons.lock_outline,
            label: 'settings.changePassword'.tr(),
            onTap: () => context.push('/settings/change-password')),

        const Divider(),

        // ── ΕΦΑΡΜΟΓΗ ──
        _SectionLabel('settings.app'.tr()),
        const _LanguageTile(),
        Consumer(
          builder: (context, ref, _) {
            final userAsync = ref.watch(currentUserDataProvider);
            return userAsync.when(
              data: (user) {
                if (user == null) return const SizedBox.shrink();
                return SwitchListTile(
                  secondary: const Icon(Icons.lock_outline,
                      color: AppColors.textSecondary),
                  title: Text('settings.privateProfile'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(
                    user.isPrivateProfile
                        ? 'settings.privateOn'.tr()
                        : 'settings.privateOff'.tr(),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  value: user.isPrivateProfile,
                  activeThumbColor: AppColors.primary,
                  onChanged: (value) async {
                    final uid = ref.read(currentUserProvider)?.uid;
                    if (uid == null) return;
                    try {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({'isPrivateProfile': value});
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${'common.error'.tr()}: $e')));
                      }
                    }
                  },
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            );
          },
        ),
        _SettingsTile(
            icon: Icons.bookmark_outline,
            label: 'settings.savedListings'.tr(),
            onTap: () => context.push('/saved')),
        _SettingsTile(
            icon: Icons.block,
            label: 'settings.blockedUsers'.tr(),
            onTap: () => context.push('/settings/blocked')),
        _SettingsTile(
            icon: Icons.notifications_none,
            label: 'notifsettings.title'.tr(),
            onTap: () => context.push('/settings/notifications')),

        const Divider(),

        // ── ΥΠΟΣΤΗΡΙΞΗ ──
        _SectionLabel('settings.support'.tr()),
        _SettingsTile(
            icon: Icons.help_outline,
            label: 'settings.help'.tr(),
            onTap: () => context.push('/settings/help')),
        _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            label: 'settings.privacyPolicy'.tr(),
            onTap: () => launchUrl(
                Uri.parse(LegalUrls.privacy(context.locale.languageCode)),
                mode: LaunchMode.externalApplication)),
        _SettingsTile(
            icon: Icons.description_outlined,
            label: 'settings.terms'.tr(),
            onTap: () => launchUrl(
                Uri.parse(LegalUrls.terms(context.locale.languageCode)),
                mode: LaunchMode.externalApplication)),

        const Divider(),

        // ── ΠΛΗΡΟΦΟΡΙΕΣ ──
        _SectionLabel('settings.info'.tr()),
        const _AppVersionTile(),

        const Divider(),

        // ── ΕΞΟΔΟΣ ──
        _SettingsTile(
            icon: Icons.logout,
            label: 'settings.logout'.tr(),
            color: AppColors.danger,
            onTap: () => _confirmLogout(context, ref)),
        _SettingsTile(
            icon: Icons.delete_forever_outlined,
            label: 'settings.deleteAccount'.tr(),
            color: AppColors.danger,
            onTap: () => context.push('/delete-account')),
      ]),
    );
  }
}

class _AppVersionTile extends StatelessWidget {
  const _AppVersionTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.hasData
            ? '${snapshot.data!.version} (build ${snapshot.data!.buildNumber})'
            : '...';
        return ListTile(
          leading: const Icon(Icons.info_outline,
              color: AppColors.textSecondary, size: 20),
          title: Text('settings.appVersion'.tr(),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          subtitle: Text(version,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        );
      },
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  static String _labelFor(String code) {
    switch (code) {
      case 'el':
        return 'language.el'.tr();
      case 'es':
        return 'language.es'.tr();
      default:
        return 'language.en'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = context.locale.languageCode;
    return ListTile(
      leading: const Icon(Icons.language,
          color: AppColors.textSecondary, size: 20),
      title: Text('settings.language'.tr(),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      subtitle: Text(_labelFor(current),
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right,
          color: AppColors.textHint, size: 18),
      onTap: () => _showPicker(context, current),
    );
  }

  void _showPicker(BuildContext context, String current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('language.title'.tr(),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
          for (final locale in const [
            Locale('el'),
            Locale('en'),
            Locale('es')
          ])
            ListTile(
              title: Text(_labelFor(locale.languageCode),
                  style: const TextStyle(color: AppColors.textPrimary)),
              trailing: locale.languageCode == current
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                context.setLocale(locale);
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) {
                  FcmService.saveLanguage(uid, locale.languageCode);
                }
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
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
