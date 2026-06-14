import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import 'package:shareit/features/listings/data/listing_model.dart';
import 'marker_image_cache.dart';

class MapClusterBuilder {
  /// [scale] = πολλαπλασιαστής μεγέθους (0.5 - 1.0) με βάση το zoom.
  static Future<BitmapDescriptor> build({
    required int count,
    required List<ListingModel> listings,
    required int offerCount,
    required int seekCount,
    double scale = 1.0,
  }) async {
    final width = 130.0 * scale;
    final height = 70.0 * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final bgPaint = Paint()..color = const Color(0xFF161B24);
    final dominantColor =
        offerCount >= seekCount ? AppColors.offer : AppColors.seek;
    final borderPaint = Paint()
      ..color = dominantColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * scale;

    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, width, height), Radius.circular(14 * scale));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Unique user avatars (max 3)
    final seenUserIds = <String>{};
    final avatars = <String?>[];
    for (final listing in listings) {
      if (seenUserIds.contains(listing.userId)) continue;
      seenUserIds.add(listing.userId);
      avatars.add(listing.userAvatarUrl);
      if (avatars.length >= 3) break;
    }

    final avatarSize = 38.0 * scale;
    final avatarSpacing = 4.0 * scale;
    final totalAvatarsWidth =
        avatars.length * avatarSize + (avatars.length - 1) * avatarSpacing;
    final avatarsStartX = 10.0 * scale;
    final avatarY = 16.0 * scale;

    for (var i = 0; i < avatars.length; i++) {
      final x = avatarsStartX + i * (avatarSize + avatarSpacing);
      final rect = Rect.fromLTWH(x, avatarY, avatarSize, avatarSize);
      final clipRRect =
          RRect.fromRectAndRadius(rect, Radius.circular(8 * scale));

      ui.Image? image;
      if (avatars[i] != null && avatars[i]!.isNotEmpty) {
        // FIX: HTTP-based loader (αξιόπιστο με Firebase URLs)
        image = await MarkerImageCache.load(avatars[i]!);
      }

      if (image != null) {
        canvas.save();
        canvas.clipRRect(clipRRect);
        final srcSize = image.width < image.height ? image.width : image.height;
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
      } else {
        _drawAvatarPlaceholder(canvas, rect, dominantColor, i, scale);
      }

      canvas.drawRRect(
        clipRRect,
        Paint()
          ..color = const Color(0xFF161B24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale,
      );
    }

    // Count badge δεξιά
    final countText = count > 99 ? '99+' : '$count';
    final countX = avatarsStartX + totalAvatarsWidth + 8 * scale;
    final countCenterY = avatarY + avatarSize / 2;

    final countPainter = TextPainter(
      text: TextSpan(
        text: countText,
        style: TextStyle(
            color: Colors.white,
            fontSize: 14 * scale,
            fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeWidth = countPainter.width + 14 * scale;
    final badgeRect = Rect.fromCenter(
        center: Offset(countX + badgeWidth / 2, countCenterY),
        width: badgeWidth,
        height: 22 * scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, Radius.circular(11 * scale)),
      Paint()..color = dominantColor,
    );

    countPainter.paint(
        canvas,
        Offset(badgeRect.center.dx - countPainter.width / 2,
            badgeRect.center.dy - countPainter.height / 2));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static void _drawAvatarPlaceholder(
      Canvas canvas, Rect rect, Color color, int index, double scale) {
    final colors = [
      AppColors.offer.withValues(alpha: 0.3),
      AppColors.seek.withValues(alpha: 0.3),
      AppColors.deal.withValues(alpha: 0.3),
    ];
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(8 * scale)),
      Paint()..color = colors[index % colors.length],
    );

    final iconPainter = TextPainter(
      text: TextSpan(text: '👤', style: TextStyle(fontSize: 22 * scale)),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
        canvas,
        Offset(rect.center.dx - iconPainter.width / 2,
            rect.center.dy - iconPainter.height / 2));
  }
}
