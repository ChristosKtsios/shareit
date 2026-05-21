import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../../features/listings/data/listing_model.dart';

class MapMarkerBuilder {
  static Future<BitmapDescriptor> buildMarker({
    required ListingModel listing,
  }) async {
    final isOffer = listing.type == ListingType.offer;
    final color = isOffer ? AppColors.offer : AppColors.seek;
    final emoji = isOffer ? '🤲' : '🔍';

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const width = 180.0;
    const height = 110.0;

    // Background
    final bgPaint = Paint()..color = const Color(0xFF161B24);
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final rrect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, width, height - 12),
        const Radius.circular(16));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Triangle tail
    final path = Path()
      ..moveTo(width / 2 - 10, height - 12)
      ..lineTo(width / 2 + 10, height - 12)
      ..lineTo(width / 2, height)
      ..close();
    canvas.drawPath(path, bgPaint);
    canvas.drawPath(path, borderPaint);

    // Type badge top-left
    final badgePaint = Paint()..color = color.withValues(alpha: 0.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 8, 60, 22), const Radius.circular(11)),
      badgePaint,
    );
    final emojiPainter = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: 14)),
      textDirection: TextDirection.ltr,
    )..layout();
    emojiPainter.paint(canvas, const Offset(12, 12));

    final typeText = isOffer ? 'Προσφέρω' : 'Αναζητώ';
    final typePainter = TextPainter(
      text: TextSpan(
          text: typeText,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    typePainter.paint(canvas, const Offset(30, 14));

    // Title (truncated)
    final title = listing.title.length > 22
        ? '${listing.title.substring(0, 22)}...'
        : listing.title;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
            color: Color(0xFFF0F4FF),
            fontSize: 12,
            fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 16);
    titlePainter.paint(canvas, const Offset(8, 38));

    // Βεντάλια φωτογραφιών αγγελίας (max 3)
    if (listing.imageUrls.isNotEmpty) {
      final maxPhotos = listing.imageUrls.length.clamp(0, 3);
      const photoSize = 32.0;
      const photoSpacing = 6.0;
      final totalWidth = maxPhotos * photoSize + (maxPhotos - 1) * photoSpacing;
      final startX = (width - totalWidth) / 2;
      const photoY = 58.0;

      for (var i = 0; i < maxPhotos; i++) {
        final x = startX + i * (photoSize + photoSpacing);
        try {
          final image = await _loadNetworkImage(listing.imageUrls[i]);
          if (image != null) {
            final rect = Rect.fromLTWH(x, photoY, photoSize, photoSize);
            final clipPath = Path()
              ..addRRect(
                  RRect.fromRectAndRadius(rect, const Radius.circular(8)));
            canvas.save();
            canvas.clipPath(clipPath);

            final srcSize =
                image.width < image.height ? image.width : image.height;
            final srcX = (image.width - srcSize) / 2;
            final srcY = (image.height - srcSize) / 2;
            canvas.drawImageRect(
              image,
              Rect.fromLTWH(srcX.toDouble(), srcY.toDouble(),
                  srcSize.toDouble(), srcSize.toDouble()),
              rect,
              Paint(),
            );
            canvas.restore();

            // Border
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(8)),
              Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
          } else {
            _drawPlaceholder(canvas, x, photoY, photoSize, color);
          }
        } catch (_) {
          _drawPlaceholder(canvas, x, photoY, photoSize, color);
        }
      }

      // "+X" αν έχει παραπάνω από 3
      if (listing.imageUrls.length > 3) {
        final overflowPainter = TextPainter(
          text: TextSpan(
              text: '+${listing.imageUrls.length - 3}',
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        overflowPainter.paint(
            canvas,
            Offset(width - overflowPainter.width - 8,
                photoY + photoSize - overflowPainter.height));
      }
    } else {
      // Δεν υπάρχουν φωτογραφίες — δείξε tags
      if (listing.tags.isNotEmpty) {
        final tagText = '#${listing.tags.first}';
        final tagPainter = TextPainter(
          text: TextSpan(
              text: tagText,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          textDirection: TextDirection.ltr,
        )..layout();
        tagPainter.paint(canvas, Offset((width - tagPainter.width) / 2, 70));
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static void _drawPlaceholder(
      Canvas canvas, double x, double y, double size, Color color) {
    final rect = Rect.fromLTWH(x, y, size, size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = color.withValues(alpha: 0.15),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// Φορτώνει image από URL ως ui.Image (για canvas drawing)
  static Future<ui.Image?> _loadNetworkImage(String url) async {
    try {
      final NetworkAssetBundle bundle = NetworkAssetBundle(Uri.parse(url));
      final ByteData data = await bundle.load(url);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 100,
        targetHeight: 100,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}
