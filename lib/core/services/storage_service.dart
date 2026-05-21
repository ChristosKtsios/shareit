import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  static final _storage = FirebaseStorage.instance;
  static const _uuid = Uuid();

  static Future<String> uploadImage(File file, String folder) async {
    final id  = _uuid.v4();
    final ext = file.path.split('.').last;
    final ref = _storage.ref('$folder/$id.$ext');
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  static Future<List<String>> uploadImages(List<File> files, String folder) async =>
      await Future.wait(files.map((f) => uploadImage(f, folder)));

  static Future<void> deleteImage(String url) async {
    try { await _storage.refFromURL(url).delete(); } catch (_) {}
  }
}
