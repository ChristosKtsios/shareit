import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_colors.dart';

enum MediaType { image, video }

class PickedMedia {
  final File file;
  final MediaType type;
  PickedMedia({required this.file, required this.type});
}

class MediaPickerService {
  final _picker = ImagePicker();
  final _storage = FirebaseStorage.instance;

  /// Τυλίγει ένα pick σε try/catch: σε άρνηση άδειας (PlatformException, π.χ.
  /// camera_access_denied / photo_access_denied) κλείνει το sheet και δείχνει
  /// ευγενικό μήνυμα αντί να κρασάρει η εφαρμογή.
  Future<void> _handlePick({
    required BuildContext outer,
    required BuildContext sheetCtx,
    required Future<XFile?> Function() pick,
    required MediaType type,
  }) async {
    try {
      final p = await pick();
      if (!sheetCtx.mounted) return;
      Navigator.of(sheetCtx).pop(
          p == null ? null : PickedMedia(file: File(p.path), type: type));
    } on PlatformException catch (_) {
      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
      if (outer.mounted) {
        ScaffoldMessenger.of(outer).showSnackBar(
          SnackBar(content: Text('mediapick.permissionNeeded'.tr())),
        );
      }
    }
  }

  Future<PickedMedia?> showPickerSheet(BuildContext context) async {
    return await showModalBottomSheet<PickedMedia>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('mediapick.title'.tr(),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: Text('mediapick.photoGallery'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () => _handlePick(
                outer: context,
                sheetCtx: ctx,
                type: MediaType.image,
                pick: () => _picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 75),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: Text('mediapick.photoCamera'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () => _handlePick(
                outer: context,
                sheetCtx: ctx,
                type: MediaType.image,
                pick: () => _picker.pickImage(
                    source: ImageSource.camera, imageQuality: 75),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: AppColors.primary),
              title: Text('mediapick.videoGallery'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () => _handlePick(
                outer: context,
                sheetCtx: ctx,
                type: MediaType.video,
                pick: () => _picker.pickVideo(
                    source: ImageSource.gallery,
                    maxDuration: const Duration(minutes: 2)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: AppColors.primary),
              title: Text('mediapick.videoCamera'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () => _handlePick(
                outer: context,
                sheetCtx: ctx,
                type: MediaType.video,
                pick: () => _picker.pickVideo(
                    source: ImageSource.camera,
                    maxDuration: const Duration(minutes: 2)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<String> uploadToStorage({
    required File file,
    required String folder,
    required MediaType type,
  }) async {
    final ext = type == MediaType.image ? 'jpg' : 'mp4';
    final fileName = '${const Uuid().v4()}.$ext';
    final ref = _storage.ref().child('$folder/$fileName');
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }
}
