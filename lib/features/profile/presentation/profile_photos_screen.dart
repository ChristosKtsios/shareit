import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/profile_provider.dart';

class ProfilePhotosScreen extends ConsumerStatefulWidget {
  const ProfilePhotosScreen({super.key});
  @override
  ConsumerState<ProfilePhotosScreen> createState() =>
      _ProfilePhotosScreenState();
}

class _ProfilePhotosScreenState extends ConsumerState<ProfilePhotosScreen> {
  bool _uploading = false;
  List<String> _photos = [];
  String? _profilePhoto;
  bool _initialized = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    // Πολλαπλή επιλογή — απεριόριστες φωτογραφίες
    final files = await picker.pickMultiImage(
      imageQuality: 60,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final uid = ref.read(currentUserProvider)!.uid;
      final newUrls = <String>[];

      for (final file in files) {
        final storageRef = FirebaseStorage.instance.ref(
            'users/$uid/${DateTime.now().millisecondsSinceEpoch}_${newUrls.length}.jpg');
        await storageRef.putFile(File(file.path));
        newUrls.add(await storageRef.getDownloadURL());
      }

      final newPhotos = [..._photos, ...newUrls];
      // Αν δεν υπάρχει κύρια φωτό, όρισε την πρώτη που ανέβηκε
      final newProfile = _profilePhoto ?? newPhotos.first;

      setState(() {
        _photos = newPhotos;
        _profilePhoto = newProfile;
      });

      await ref.read(userRepoProvider).update(uid, {
        'photos': newPhotos,
        'avatarUrl': newProfile,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _setAsProfile(String url) async {
    final uid = ref.read(currentUserProvider)!.uid;
    setState(() => _profilePhoto = url);
    await ref.read(userRepoProvider).update(uid, {'avatarUrl': url});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Η εικόνα προφίλ ενημερώθηκε!')));
    }
  }

  Future<void> _deletePhoto(String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Διαγραφή φωτογραφίας',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Είσαι σίγουρος;',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Άκυρο')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Διαγραφή',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirm != true) return;

    final uid = ref.read(currentUserProvider)!.uid;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}

    final newPhotos = _photos.where((p) => p != url).toList();
    final newProfile = _profilePhoto == url
        ? (newPhotos.isNotEmpty ? newPhotos.first : null)
        : _profilePhoto;

    setState(() {
      _photos = newPhotos;
      _profilePhoto = newProfile;
    });

    await ref.read(userRepoProvider).update(uid, {
      'photos': newPhotos,
      'avatarUrl': newProfile,
    });
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserDataProvider);

    return userAsync.when(
      loading: () => const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: AppColors.primary))),
      error: (_, __) => const Scaffold(
          body: Center(
              child: Text('Σφάλμα',
                  style: TextStyle(color: AppColors.textSecondary)))),
      data: (user) {
        if (user == null) return const Scaffold();
        if (!_initialized) {
          _photos = List<String>.from(user.photos);
          _profilePhoto = user.avatarUrl;
          _initialized = true;
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Φωτογραφίες')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: AppColors.primary, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                    'Ανέβασε όσες φωτογραφίες θες. '
                    'Πάτα μια φωτογραφία για να την ορίσεις ως εικόνα προφίλ.',
                    style: TextStyle(color: AppColors.primary, fontSize: 12),
                  )),
                ]),
              ),
              const SizedBox(height: 16),

              // Counter + Add
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${_photos.length} φωτογραφίες',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                GestureDetector(
                  onTap: _uploading ? null : _pickAndUpload,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary, width: 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _uploading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primary))
                          : const Icon(Icons.add_photo_alternate_outlined,
                              color: AppColors.primary, size: 16),
                      const SizedBox(width: 6),
                      const Text('Προσθήκη',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // Grid
              Expanded(
                child: _photos.isEmpty
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.photo_library_outlined,
                            color: AppColors.textHint, size: 48),
                        const SizedBox(height: 12),
                        const Text('Δεν έχεις φωτογραφίες ακόμα.',
                            style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _uploading ? null : _pickAndUpload,
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 18),
                          label: const Text('Πρόσθεσε φωτογραφίες'),
                        ),
                      ]))
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8),
                        itemCount: _photos.length,
                        itemBuilder: (_, i) {
                          final url = _photos[i];
                          final isProfile = url == _profilePhoto;
                          return GestureDetector(
                            onTap: () => _setAsProfile(url),
                            child: Stack(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(url,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover),
                              ),
                              if (isProfile)
                                Positioned(
                                    top: 4,
                                    left: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: const Text('Προφίλ',
                                          style: TextStyle(
                                              color: AppColors.background,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600)),
                                    )),
                              Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => _deletePhoto(url),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: const BoxDecoration(
                                          color: AppColors.danger,
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.close,
                                          color: Colors.white, size: 14),
                                    ),
                                  )),
                            ]),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
