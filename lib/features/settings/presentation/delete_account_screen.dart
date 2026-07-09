import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _agreed = false;

  String get _confirmWord => 'delacc.confirmWord'.tr();

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    setState(() => _loading = true);

    try {
      // Cloud Function call
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('deleteUserAccount');
      final result = await callable.call();

      if (!mounted) return;

      final data = result.data as Map<dynamic, dynamic>?;
      final success = data?['success'] == true;

      if (success) {
        // Logout local state — το auth state ήδη έχει διαγραφεί στον server
        try {
          await ref.read(authRepoProvider).logout();
        } catch (_) {}

        if (!mounted) return;

        // GoRouter redirect θα πάει στο /login αυτόματα
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('delacc.deleted'.tr()),
            backgroundColor: AppColors.offer,
          ),
        );

        // Καθαρίζουμε όλο το navigation stack
        if (mounted) {
          context.go('/login');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('delacc.somethingWrong'.tr()),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'common.error'.tr()}: ${e.message ?? e.code}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'common.error'.tr()}: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete =
        _agreed && _confirmCtrl.text.trim().toUpperCase() == _confirmWord;

    return Scaffold(
      appBar: AppBar(title: Text('settings.deleteAccount'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.4), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.danger, size: 22),
                      const SizedBox(width: 8),
                      Text('delacc.warning'.tr(),
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'delacc.warningBodyShort'.tr(),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text('delacc.whatDeleted'.tr(),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),

              _DeleteItem('delacc.item1'.tr()),
              _DeleteItem('delacc.item2'.tr()),
              _DeleteItem('delacc.item3'.tr()),
              _DeleteItem('delacc.item4'.tr()),
              _DeleteItem('delacc.item5'.tr()),
              _DeleteItem('delacc.item6'.tr()),

              const SizedBox(height: 24),

              // Checkbox συμφωνίας
              Row(children: [
                Checkbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  activeColor: AppColors.danger,
                ),
                Expanded(
                  child: Text(
                    'delacc.understand'.tr(),
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                  ),
                ),
              ]),

              const SizedBox(height: 20),

              Text(
                'delacc.typeToConfirm'.tr(namedArgs: {'word': _confirmWord}),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: _confirmWord,
                ),
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: canDelete && !_loading ? _deleteAccount : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.surfaceVariant,
                  disabledForegroundColor: AppColors.textHint,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('settings.deleteAccount'.tr(),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),

              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => context.pop(),
                  child: Text('common.cancel'.tr(),
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteItem extends StatelessWidget {
  final String text;
  const _DeleteItem(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const Icon(Icons.close, color: AppColors.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
        ]),
      );
}
