import 'package:flutter/material.dart';
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
  late final TextEditingController _phoneCtrl;
  bool _loading     = false;
  bool _initialized = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserDataProvider);

    return userAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (_, __) => const Scaffold(
          body: Center(child: Text(AppStrings.errorGeneric,
              style: TextStyle(color: AppColors.textSecondary)))),
      data: (user) {
        if (user == null) return const Scaffold();
        if (!_initialized) {
          _firstCtrl  = TextEditingController(text: user.firstName);
          _lastCtrl   = TextEditingController(text: user.lastName);
          _phoneCtrl  = TextEditingController(text: user.phone);
          _initialized = true;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text(AppStrings.editProfile),
            leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.pop()),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [

              // Avatar
              Center(child: Stack(children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: AppColors.primarySurface,
                  backgroundImage: user.avatarUrl != null
                      ? NetworkImage(user.avatarUrl!) : null,
                  child: user.avatarUrl == null
                      ? Text(user.initials, style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 28, fontWeight: FontWeight.w700))
                      : null,
                ),
                Positioned(right: 0, bottom: 0,
                  child: GestureDetector(
                    onTap: () => context.push('/profile/photos'),
                    child: Container(
                      width: 28, height: 28,
                      decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt,
                          color: AppColors.background, size: 16),
                    ),
                  )),
              ])),
              const SizedBox(height: 28),

              // Όνομα
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(AppStrings.firstName,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: _firstCtrl,
                      style: const TextStyle(color: AppColors.textPrimary)),
                ])),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(AppStrings.lastName,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: _lastCtrl,
                      style: const TextStyle(color: AppColors.textPrimary)),
                ])),
              ]),
              const SizedBox(height: 16),

              // Τηλέφωνο
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(AppStrings.phone,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: AppColors.textPrimary)),
              ]),
              const SizedBox(height: 32),

              // Αποθήκευση
              ElevatedButton(
                onPressed: _loading ? null : () async {
                  setState(() => _loading = true);
                  try {
                    final uid = ref.read(currentUserProvider)!.uid;
                    await ref.read(userRepoProvider).update(uid, {
                      'firstName': _firstCtrl.text.trim(),
                      'lastName':  _lastCtrl.text.trim(),
                      'phone':     _phoneCtrl.text.trim(),
                    });
                    if (mounted) context.pop();
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(AppStrings.errorGeneric)));
                    }
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
                child: _loading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.background))
                    : const Text('Αποθήκευση'),
              ),
            ]),
          ),
        );
      },
    );
  }
}