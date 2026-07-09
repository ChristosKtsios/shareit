import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/profile_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  bool _loading = false;
  bool _initialized = false;
  bool _showOnlineStatus = true;

  @override
  void dispose() {
    if (_initialized) {
      _firstCtrl.dispose();
      _lastCtrl.dispose();
    }
    super.dispose();
  }

  void _showComingSoon(BuildContext context, String fieldName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(children: [
          const Icon(Icons.security, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Text('editProfile.changeField'.tr(namedArgs: {'field': fieldName}),
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        ]),
        content: Text(
          'editProfile.changeFieldBody'.tr(namedArgs: {'field': fieldName}),
          style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('editProfile.ok'.tr(),
                style: const TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();

    if (first.isEmpty || last.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('editProfile.nameRequired'.tr()),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final uid = ref.read(currentUserProvider)!.uid;
      await ref.read(userRepoProvider).update(uid, {
        'firstName': first,
        'lastName': last,
        'showOnlineStatus': _showOnlineStatus,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('editProfile.saved'.tr()),
            backgroundColor: AppColors.offer,
          ),
        );
        context.pop();
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.errorGeneric)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserDataProvider);

    return userAsync.when(
      loading: () => const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: AppColors.primary))),
      error: (_, __) => Scaffold(
          body: Center(
              child: Text(AppStrings.errorGeneric,
                  style: const TextStyle(color: AppColors.textSecondary)))),
      data: (user) {
        if (user == null) return const Scaffold();
        if (!_initialized) {
          _firstCtrl = TextEditingController(text: user.firstName);
          _lastCtrl = TextEditingController(text: user.lastName);
          _showOnlineStatus = user.showOnlineStatus;
          _initialized = true;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(AppStrings.editProfile),
            leading: IconButton(
                icon: const Icon(Icons.close), onPressed: () => context.pop()),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Avatar ──
                Center(
                    child: Stack(children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primarySurface,
                    backgroundImage: user.avatarUrl != null
                        ? NetworkImage(user.avatarUrl!)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(user.initials,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 28,
                                fontWeight: FontWeight.w700))
                        : null,
                  ),
                  Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () => context.push('/profile/photos'),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                              color: AppColors.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt,
                              color: AppColors.background, size: 16),
                        ),
                      )),
                ])),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/profile/photos'),
                    child: Text('editProfile.changePhoto'.tr(),
                        style: const TextStyle(
                            color: AppColors.primary, fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Section: Προσωπικά στοιχεία ──
                _SectionTitle('editProfile.personalInfo'.tr()),
                const SizedBox(height: 12),

                Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        _FieldLabel('editProfile.firstNameLabel'.tr()),
                        const SizedBox(height: 6),
                        TextField(
                            controller: _firstCtrl,
                            style:
                                const TextStyle(color: AppColors.textPrimary)),
                      ])),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        _FieldLabel('editProfile.lastNameLabel'.tr()),
                        const SizedBox(height: 6),
                        TextField(
                            controller: _lastCtrl,
                            style:
                                const TextStyle(color: AppColors.textPrimary)),
                      ])),
                ]),

                const SizedBox(height: 28),

                // ── Section: Στοιχεία επικοινωνίας ──
                _SectionTitle('editProfile.contactInfo'.tr()),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    'editProfile.changeSecurityNote'.tr(),
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 11, height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),

                // Email — read-only με Αλλαγή
                _ReadOnlyField(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: user.email,
                  onChange: () => _showComingSoon(context, 'email'),
                ),
                const SizedBox(height: 12),

                // Κινητό — read-only με Αλλαγή
                _ReadOnlyField(
                  icon: Icons.phone_outlined,
                  label: 'editProfile.mobile'.tr(),
                  value: user.phone,
                  onChange: () => context.push('/settings/change-phone'),
                ),

                const SizedBox(height: 20),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('editProfile.showOnlineStatus'.tr(),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    subtitle: Text('editProfile.showOnlineStatusSub'.tr(),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                    value: _showOnlineStatus,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => setState(() => _showOnlineStatus = v),
                  ),
                ),
                const SizedBox(height: 24),
                // ── Save button ──
                ElevatedButton(
                  onPressed: _loading ? null : () => _save(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.background))
                      : Text('common.save'.tr(),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
}

class _ReadOnlyField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onChange;

  const _ReadOnlyField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.isEmpty ? '—' : value;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: onChange,
              icon: const Icon(Icons.edit_outlined,
                  size: 14, color: AppColors.primary),
              label: Text('editProfile.change'.tr(),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(displayValue,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
