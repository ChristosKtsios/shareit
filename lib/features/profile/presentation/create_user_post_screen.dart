import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/media_picker_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/user_post_repository.dart';
import '../data/user_repository.dart';

class CreateUserPostScreen extends ConsumerStatefulWidget {
  const CreateUserPostScreen({super.key});

  @override
  ConsumerState<CreateUserPostScreen> createState() =>
      _CreateUserPostScreenState();
}

class _CreateUserPostScreenState extends ConsumerState<CreateUserPostScreen> {
  final _textCtrl = TextEditingController();
  final List<PickedMedia> _media = [];
  bool _uploading = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    if (_media.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Μέγιστο 10 αρχεία')),
      );
      return;
    }
    final picker = MediaPickerService();
    final m = await picker.showPickerSheet(context);
    if (m != null) {
      setState(() => _media.add(m));
    }
  }

  Future<void> _submit() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _media.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Γράψε κείμενο ή πρόσθεσε αρχείο')),
      );
      return;
    }

    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;

    setState(() => _uploading = true);

    try {
      // Upload όλα τα media
      final picker = MediaPickerService();
      final urls = <String>[];
      final types = <String>[];
      for (final m in _media) {
        final url = await picker.uploadToStorage(
          file: m.file,
          folder: 'userPosts/$uid',
          type: m.type,
        );
        urls.add(url);
        types.add(m.type == MediaType.image ? 'image' : 'video');
      }

      // Φόρτωσε τον user
      final user = await UserRepository().get(uid);

      await UserPostRepository().create(
        authorUid: uid,
        authorName: user?.fullName ?? 'Χρήστης',
        authorAvatar: user?.avatarUrl,
        text: text,
        mediaUrls: urls,
        mediaTypes: types,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Το post δημοσιεύθηκε!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Νέο Post'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _uploading ? null : _submit,
            child: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Text('Δημοσίευση',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    )),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Text field
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: TextField(
                controller: _textCtrl,
                maxLines: 8,
                minLines: 4,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Τι σκέφτεσαι;',
                  hintStyle: TextStyle(color: AppColors.textHint),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Media grid
            if (_media.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _media.length,
                itemBuilder: (_, i) {
                  final m = _media[i];
                  return Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: m.type == MediaType.image
                          ? Image.file(m.file,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity)
                          : Container(
                              color: AppColors.surface,
                              child: const Center(
                                child: Icon(Icons.play_circle_outline,
                                    color: AppColors.primary, size: 40),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _media.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            const SizedBox(height: 12),
            // Add media button
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickMedia,
              icon: const Icon(Icons.add_photo_alternate_outlined,
                  color: AppColors.primary),
              label: Text(
                _media.isEmpty
                    ? 'Προσθήκη φωτογραφίας/βίντεο'
                    : 'Προσθήκη ακόμα (${_media.length}/10)',
                style: const TextStyle(color: AppColors.primary),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
