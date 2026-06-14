import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Full-screen gallery viewer για τις φωτογραφίες προφίλ ενός χρήστη.
/// Ανοίγει όταν πατήσει κάποιος το avatar στο προφίλ.
///
/// Χρήση:
///   showProfilePhotoViewer(context, photos: user.photos, name: user.fullName);
class ProfilePhotoViewer extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  final String? name;

  const ProfilePhotoViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
    this.name,
  });

  @override
  State<ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends State<ProfilePhotoViewer> {
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable photos
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  widget.photos[i],
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

          // Top bar (name + close)
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
                if (widget.name != null)
                  Expanded(
                    child: Text(
                      widget.name!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),

          // Bottom counter + dots
          if (widget.photos.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.photos.length,
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
                    '${_current + 1} / ${widget.photos.length}',
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
  int initialIndex = 0,
  String? name,
}) {
  if (photos.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProfilePhotoViewer(
        photos: photos,
        initialIndex: initialIndex,
        name: name,
      ),
    ),
  );
}
