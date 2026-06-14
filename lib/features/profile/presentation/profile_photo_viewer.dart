import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';

/// Full-screen gallery viewer για τις φωτογραφίες προφίλ ενός χρήστη.
/// Ανοίγει όταν πατήσει κάποιος το avatar στο προφίλ.
///
/// Αν [isOwner] == true:
///   - εμφανίζει "+" για προσθήκη φωτογραφιών
///   - εμφανίζει "⋮" με επιλογές: Ορισμός ως προφίλ / Διαγραφή
/// Αν [isOwner] == false:
///   - μόνο προβολή (swipe), χωρίς κουμπιά
class ProfilePhotoViewer extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  final String? name;
  final bool isOwner;
  final String uid;
  final String? currentAvatarUrl;

  const ProfilePhotoViewer({
    super.key,
    required this.photos,
    required this.uid,
    this.initialIndex = 0,
    this.name,
    this.isOwner = false,
    this.currentAvatarUrl,
  });

  @override
  State<ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends State<ProfilePhotoViewer> {
  late final PageController _controller;
  late int _current;
  late List<String> _photos;
  late String? _avatarUrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _photos = List<String>.from(widget.photos);
    _avatarUrl = widget.currentAvatarUrl;
    _current =
        widget.initialIndex.clamp(0, _photos.isEmpty ? 0 : _photos.length - 1);
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(
        imageQuality: 60, maxWidth: 1200, maxHeight: 1200);
    if (files.isEmpty) return;

    setState(() => _busy = true);
    try {
      final newUrls = <String>[];
      for (final file in files) {
        final ref = FirebaseStorage.instance.ref(
            'users/${widget.uid}/${DateTime.now().millisecondsSinceEpoch}_${newUrls.length}.jpg');
        await ref.putFile(File(file.path));
        newUrls.add(await ref.getDownloadURL());
      }
      final updated = [..._photos, ...newUrls];
      final newAvatar = _avatarUrl ?? updated.first;

      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set(
          {'photos': updated, 'avatarUrl': newAvatar}, SetOptions(merge: true));

      setState(() {
        _photos = updated;
        _avatarUrl = newAvatar;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAsProfile() async {
    if (_photos.isEmpty) return;
    final url = _photos[_current];
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .set({'avatarUrl': url}, SetOptions(merge: true));
    setState(() => _avatarUrl = url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ορίστηκε ως εικόνα προφίλ!')));
    }
  }

  Future<void> _deleteCurrent() async {
    if (_photos.isEmpty) return;
    final url = _photos[_current];

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
              child: const Text('Άκυρο',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Διαγραφή',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}

      final updated = _photos.where((p) => p != url).toList();
      final newAvatar = _avatarUrl == url
          ? (updated.isNotEmpty ? updated.first : null)
          : _avatarUrl;

      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set(
          {'photos': updated, 'avatarUrl': newAvatar}, SetOptions(merge: true));

      if (!mounted) return;
      if (updated.isEmpty) {
        Navigator.pop(context); // δεν έμειναν φωτό -> κλείσε
        return;
      }
      setState(() {
        _photos = updated;
        _avatarUrl = newAvatar;
        _current = _current.clamp(0, _photos.length - 1);
      });
      _controller.jumpToPage(_current);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showOptionsMenu() {
    final isCurrentProfile =
        _photos.isNotEmpty && _photos[_current] == _avatarUrl;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isCurrentProfile)
            ListTile(
              leading: const Icon(Icons.account_circle_outlined,
                  color: AppColors.primary),
              title: const Text('Ορισμός ως εικόνα προφίλ',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _setAsProfile();
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.danger),
            title: const Text('Διαγραφή φωτογραφίας',
                style: TextStyle(color: AppColors.danger)),
            onTap: () {
              Navigator.pop(context);
              _deleteCurrent();
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentProfile =
        _photos.isNotEmpty && _photos[_current] == _avatarUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable photos
          if (_photos.isNotEmpty)
            PageView.builder(
              controller: _controller,
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    _photos[i],
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white38, size: 48),
                    ),
                  ),
                ),
              ),
            ),

          // Top bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            right: 8,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.name != null)
                        Text(
                          widget.name!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (isCurrentProfile)
                        const Text('Εικόνα προφίλ',
                            style: TextStyle(
                                color: AppColors.primary, fontSize: 11)),
                    ],
                  ),
                ),
                // Owner controls: + και ⋮
                if (widget.isOwner) ...[
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        color: Colors.white),
                    onPressed: _busy ? null : _addPhotos,
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed:
                        (_busy || _photos.isEmpty) ? null : _showOptionsMenu,
                  ),
                ],
              ],
            ),
          ),

          // Busy overlay
          if (_busy)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),

          // Bottom counter + dots
          if (_photos.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _photos.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _current ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _current
                              ? AppColors.primary
                              : Colors.white38,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_current + 1} / ${_photos.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Helper για να ανοίξεις τον viewer εύκολα από οπουδήποτε.
void showProfilePhotoViewer(
  BuildContext context, {
  required List<String> photos,
  required String uid,
  int initialIndex = 0,
  String? name,
  bool isOwner = false,
  String? currentAvatarUrl,
}) {
  if (photos.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProfilePhotoViewer(
        photos: photos,
        uid: uid,
        initialIndex: initialIndex,
        name: name,
        isOwner: isOwner,
        currentAvatarUrl: currentAvatarUrl,
      ),
    ),
  );
}
