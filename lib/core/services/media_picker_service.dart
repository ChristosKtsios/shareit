import 'dart:io';
import 'package:flutter/material.dart';
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
            const Text('Επιλογή Πολυμέσου',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Φωτογραφία από συλλογή',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () async {
                final p = await _picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 75);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(p == null
                    ? null
                    : PickedMedia(file: File(p.path), type: MediaType.image));
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Τραβάω φωτογραφία τώρα',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () async {
                final p = await _picker.pickImage(
                    source: ImageSource.camera, imageQuality: 75);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(p == null
                    ? null
                    : PickedMedia(file: File(p.path), type: MediaType.image));
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: AppColors.primary),
              title: const Text('Βίντεο από συλλογή',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () async {
                final p = await _picker.pickVideo(
                    source: ImageSource.gallery,
                    maxDuration: const Duration(minutes: 2));
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(p == null
                    ? null
                    : PickedMedia(file: File(p.path), type: MediaType.video));
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: AppColors.primary),
              title: const Text('Τραβάω βίντεο τώρα',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () async {
                final p = await _picker.pickVideo(
                    source: ImageSource.camera,
                    maxDuration: const Duration(minutes: 2));
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(p == null
                    ? null
                    : PickedMedia(file: File(p.path), type: MediaType.video));
              },
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
