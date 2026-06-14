import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../../features/listings/data/listing_model.dart';
import 'marker_image_cache.dart';
import 'user_map_cache.dart';

class MapMarkerBuilder {
  /// [scale] = πολλαπλασιαστής μεγέθους (0.5 - 1.0) με βάση το zoom.
  static Future<BitmapDescriptor> buildMarker({
    required ListingModel listing,
    double scale = 1.0,
  }) async {
    final isOffer = listing.type == ListingType.offer;
    final color = isOffer ? AppColors.offer : AppColors.seek;
    final emoji = isOffer ? '🤲' : '🔍';

    // ── Φόρτωσε live user info (cached) ──
    // Αν το user document υπάρχει, χρησιμοποιεί το LIVE όνομα/avatar.
    // Αν αποτύχει, fallback στα static listing.userFirstName/AvatarUrl.
    final userInfo = await UserMapCache.get(listing.userId);
    final displayName = (userInfo != null && userInfo.firstName.isNotEmpty)
        ? userInfo.firstName
        : (listing.userFirstName.isNotEmpty
            ? listing.userFirstName
            : 'Χρήστης');
    final displayInitial = (userInfo != null && userInfo.initial != '?')
        ? userInfo.initial
        : (listing.userFirstName.isNotEmpty
            ? listing.userFirstName[0].toUpperCase()
            : '?');
    final avatarUrl = userInfo?.avatarUrl ?? listing.userAvatarUrl;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final width = 180.0 * scale;
    final height = 110.0 * scale;

    final bgPaint = Paint()..color = const Color(0xFF161B24);
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * scale;

    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, width, height - 12 * scale),
        Radius.circular(16 * scale));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Triangle tail
    final path = Path()
      ..moveTo(width / 2 - 10 * scale, height - 12 * scale)
      ..lineTo(width / 2 + 10 * scale, height - 12 * scale)
      ..lineTo(width / 2, height)
      ..close();
    canvas.drawPath(path, bgPaint);
    canvas.drawPath(path, borderPaint);

    // Type badge top-left
    final badgePaint = Paint()..color = color.withValues(alpha: 0.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(8 * scale, 8 * scale, 60 * scale, 22 * scale),
          Radius.circular(11 * scale)),
      badgePaint,
    );
    final emojiPainter = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: 14 * scale)),
      textDirection: TextDirection.ltr,
    )..layout();
    emojiPainter.paint(canvas, Offset(12 * scale, 12 * scale));

    final typeText = isOffer ? 'Προσφέρω' : 'Αναζητώ';
    final typePainter = TextPainter(
      text: TextSpan(
          text: typeText,
          style: TextStyle(
              color: color, fontSize: 10 * scale, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    typePainter.paint(canvas, Offset(30 * scale, 14 * scale));

    // ── Avatar χρήστη (στρογγυλό) δίπλα στον τίτλο ──
    final avatarSize = 20.0 * scale;
    final avatarX = 8.0 * scale;
    final avatarY = 36.0 * scale;
    final avatarCenter =
        Offset(avatarX + avatarSize / 2, avatarY + avatarSize / 2);
    final avatarRadius = avatarSize / 2;

    ui.Image? avatarImage;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarImage = await MarkerImageCache.load(avatarUrl);
    }

    if (avatarImage != null) {
      canvas.save();
      final clip = Path()
        ..addOval(Rect.fromCircle(center: avatarCenter, radius: avatarRadius));
      canvas.clipPath(clip);
      final srcSize = avatarImage.width < avatarImage.height
          ? avatarImage.width
          : avatarImage.height;
      final srcX = (avatarImage.width - srcSize) / 2;
      final srcY = (avatarImage.height - srcSize) / 2;
      canvas.drawImageRect(
        avatarImage,
        Rect.fromLTWH(srcX.toDouble(), srcY.toDouble(), srcSize.toDouble(),
            srcSize.toDouble()),
        Rect.fromCircle(center: avatarCenter, radius: avatarRadius),
        Paint(),
      );
      canvas.restore();
      canvas.drawCircle(
        avatarCenter,
        avatarRadius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scale,
      );
    } else {
      // Fallback: αρχικό γράμμα ονόματος σε χρωματιστό κύκλο
      canvas.drawCircle(avatarCenter, avatarRadius,
          Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(
        avatarCenter,
        avatarRadius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scale,
      );
      final initialPainter = TextPainter(
        text: TextSpan(
            text: displayInitial,
            style: TextStyle(
                color: color,
                fontSize: 11 * scale,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      initialPainter.paint(
          canvas,
          Offset(avatarCenter.dx - initialPainter.width / 2,
              avatarCenter.dy - initialPainter.height / 2));
    }

    // ── Title με το ΟΝΟΜΑ του χρήστη + τίτλο της αγγελίας ──
    // Format: "Όνομα · Τίτλος αγγελίας"
    final titleX = avatarX + avatarSize + 6 * scale;
    final maxTitleLen = 14;
    final shortTitle = listing.title.length > maxTitleLen
        ? '${listing.title.substring(0, maxTitleLen)}...'
        : listing.title;

    final maxWidthForText = width - titleX - 8 * scale;

    // Πρώτη γραμμή: όνομα χρήστη (έντονο, primary χρώμα)
    final namePainter = TextPainter(
      text: TextSpan(
        text: displayName,
        style: TextStyle(
            color: color, fontSize: 11 * scale, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidthForText);
    namePainter.paint(canvas, Offset(titleX, avatarCenter.dy - avatarRadius));

    // Δεύτερη γραμμή: τίτλος αγγελίας
    final titlePainter = TextPainter(
      text: TextSpan(
        text: shortTitle,
        style: TextStyle(
            color: const Color(0xFFF0F4FF),
            fontSize: 10 * scale,
            fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidthForText);
    titlePainter.paint(canvas, Offset(titleX, avatarCenter.dy + 1 * scale));

    // Βεντάλια φωτογραφιών αγγελίας (max 3)
    if (listing.imageUrls.isNotEmpty) {
      final maxPhotos = listing.imageUrls.length.clamp(0, 3);
      final photoSize = 32.0 * scale;
      final photoSpacing = 6.0 * scale;
      final totalWidth = maxPhotos * photoSize + (maxPhotos - 1) * photoSpacing;
      final startX = (width - totalWidth) / 2;
      final photoY = 58.0 * scale;

      for (var i = 0; i < maxPhotos; i++) {
        final x = startX + i * (photoSize + photoSpacing);
        final rect = Rect.fromLTWH(x, photoY, photoSize, photoSize);
        final image = await MarkerImageCache.load(listing.imageUrls[i]);
        if (image != null) {
          final clipPath = Path()
            ..addRRect(
                RRect.fromRectAndRadius(rect, Radius.circular(8 * scale)));
          canvas.save();
          canvas.clipPath(clipPath);

          final srcSize =
              image.width < image.height ? image.width : image.height;
          final srcX = (image.width - srcSize) / 2;
          final srcY = (image.height - srcSize) / 2;
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(srcX.toDouble(), srcY.toDouble(), srcSize.toDouble(),
                srcSize.toDouble()),
            rect,
            Paint(),
          );
          canvas.restore();

          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(8 * scale)),
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 * scale,
          );
        } else {
          _drawPlaceholder(canvas, x, photoY, photoSize, color, scale);
        }
      }

      if (listing.imageUrls.length > 3) {
        final overflowPainter = TextPainter(
          text: TextSpan(
              text: '+${listing.imageUrls.length - 3}',
              style: TextStyle(
                  color: color,
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        overflowPainter.paint(
            canvas,
            Offset(width - overflowPainter.width - 8 * scale,
                photoY + photoSize - overflowPainter.height));
      }
    } else {
      if (listing.tags.isNotEmpty) {
        final tagText = '#${listing.tags.first}';
        final tagPainter = TextPainter(
          text: TextSpan(
              text: tagText,
              style: TextStyle(
                  color: color,
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w500)),
          textDirection: TextDirection.ltr,
        )..layout();
        tagPainter.paint(
            canvas, Offset((width - tagPainter.width) / 2, 70 * scale));
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static void _drawPlaceholder(Canvas canvas, double x, double y, double size,
      Color color, double scale) {
    final rect = Rect.fromLTWH(x, y, size, size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(8 * scale)),
      Paint()..color = color.withValues(alpha: 0.15),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(8 * scale)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale,
    );
  }
}
