import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class ListingImagesScreen extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  const ListingImagesScreen({super.key, required this.imageUrls, this.initialIndex = 0});
  @override
  State<ListingImagesScreen> createState() => _ListingImagesScreenState();
}

class _ListingImagesScreenState extends State<ListingImagesScreen> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('${_current + 1} / ${widget.imageUrls.length}',
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
      body: PageView.builder(
        controller: _ctrl,
        onPageChanged: (i) => setState(() => _current = i),
        itemCount: widget.imageUrls.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: Image.network(widget.imageUrls[i],
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 48)),
          ),
        ),
      ),
    );
  }
}
