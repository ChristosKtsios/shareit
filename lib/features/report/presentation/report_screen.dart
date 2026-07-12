import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/report_model.dart';
import '../providers/report_provider.dart';

class ReportScreen extends ConsumerStatefulWidget {
  final String targetUid;
  final String? listingId;
  final String? chatId;
  final String? messageId;

  /// Αναφορά περιεχομένου (post ή σχόλιο σε post).
  final String? postCollection; // 'wallPosts' | 'userPosts'
  final String? postId;
  final String? commentId;

  const ReportScreen({super.key, required this.targetUid, this.listingId,
      this.chatId, this.messageId,
      this.postCollection, this.postId, this.commentId});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ReportReason? _reason;
  final _detailsCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _detailsCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_reason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('report.chooseReason'.tr())));
      return;
    }
    setState(() => _loading = true);
    try {
      final uid = ref.read(currentUserProvider)!.uid;
      await reportUser(
        reporterUid: uid,
        targetUid:   widget.targetUid,
        reason:      _reason!,
        details:     _detailsCtrl.text.trim().isNotEmpty ? _detailsCtrl.text.trim() : null,
        listingId:   widget.listingId,
        chatId:      widget.chatId,
        messageId:   widget.messageId,
        postCollection: widget.postCollection,
        postId:      widget.postId,
        commentId:   widget.commentId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('report.submitted'.tr())));
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('report.errorRetry'.tr())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('chatx.report'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('report.whatReason'.tr(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),

          ...ReportReason.values.map((r) => _ReasonTile(
            label:    r.label,
            selected: _reason == r,
            onTap:    () => setState(() => _reason = r),
          )),
          const SizedBox(height: 20),

          Text('report.moreDetails'.tr(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _detailsCtrl,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(hintText: 'report.describeProblem'.tr()),
          ),
          const Spacer(),

          ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: _loading
                ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('report.submit'.tr()),
          ),
        ]),
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _ReasonTile({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.danger.withValues(alpha: 0.1) : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.danger : AppColors.border,
          width: selected ? 1.5 : 0.5),
      ),
      child: Text(label,
          style: TextStyle(
            color: selected ? AppColors.danger : AppColors.textPrimary,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          )),
    ),
  );
}
