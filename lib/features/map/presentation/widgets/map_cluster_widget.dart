import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import 'package:shareit/features/listings/data/listing_model.dart';

class MapClusterBuilder {
  static Future<BitmapDescriptor> build({
    required int count,
    required List<ListingModel> listings,
    required int offerCount,
    required int seekCount,
  }) async {
    const width = 130.0;
    const height = 70.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Background — dark με border χρώματος ανάλογα κυριαρχία
    final bgPaint = Paint()..color = const Color(0xFF161B24);
    final dominantColor =
        offerCount >= seekCount ? AppColors.offer : AppColors.seek;
    final borderPaint = Paint()
      ..color = dominantColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final rrect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, width, height), const Radius.circular(14));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Συλλογή unique user avatars (max 3) από τις αγγελίες στο cluster
    final seenUserIds = <String>{};
    final avatars = <String?>[];
    for (final listing in listings) {
      if (seenUserIds.contains(listing.userId)) continue;
      seenUserIds.add(listing.userId);
      avatars.add(listing.userAvatarUrl);
      if (avatars.length >= 3) break;
    }

    // Βεντάλια από τετράγωνα rounded avatars
    const avatarSize = 38.0;
    const avatarSpacing = 4.0;
    final totalAvatarsWidth =
        avatars.length * avatarSize + (avatars.length - 1) * avatarSpacing;
    final avatarsStartX = 10.0;
    const avatarY = 16.0;

    for (var i = 0; i < avatars.length; i++) {
      final x = avatarsStartX + i * (avatarSize + avatarSpacing);
      final rect = Rect.fromLTWH(x, avatarY, avatarSize, avatarSize);
      final clipRRect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

      if (avatars[i] != null && avatars[i]!.isNotEmpty) {
        try {
          final image = await _loadNetworkImage(avatars[i]!);
          if (image != null) {
            canvas.save();
            canvas.clipRRect(clipRRect);

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
          } else {
            _drawAvatarPlaceholder(canvas, rect, dominantColor, i);
          }
        } catch (_) {
          _drawAvatarPlaceholder(canvas, rect, dominantColor, i);
        }
      } else {
        _drawAvatarPlaceholder(canvas, rect, dominantColor, i);
      }

      // Border γύρω από το avatar
      canvas.drawRRect(
        clipRRect,
        Paint()
          ..color = const Color(0xFF161B24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Count badge δεξιά
    final countText = count > 99 ? '99+' : '$count';
    final countX = avatarsStartX + totalAvatarsWidth + 8;
    final countCenterY = avatarY + avatarSize / 2;

    // Badge background
    final countPainter = TextPainter(
      text: TextSpan(
        text: countText,
        style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeWidth = countPainter.width + 14;
    final badgeRect = Rect.fromCenter(
        center: Offset(countX + badgeWidth / 2, countCenterY),
        width: badgeWidth,
        height: 22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(11)),
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
      Canvas canvas, Rect rect, Color color, int index) {
    // Διαφορετική χρωματική απόχρωση για κάθε avatar που δεν έχει φωτό
    final colors = [
      AppColors.offer.withValues(alpha: 0.3),
      AppColors.seek.withValues(alpha: 0.3),
      AppColors.deal.withValues(alpha: 0.3),
    ];
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = colors[index % colors.length],
    );

    // Person icon
    final iconPainter = TextPainter(
      text: const TextSpan(text: '👤', style: TextStyle(fontSize: 22)),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
        canvas,
        Offset(rect.center.dx - iconPainter.width / 2,
            rect.center.dy - iconPainter.height / 2));
  }

  /// Φορτώνει image από URL ως ui.Image
  static Future<ui.Image?> _loadNetworkImage(String url) async {
    try {
      final bundle = NetworkAssetBundle(Uri.parse(url));
      final data = await bundle.load(url);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 80,
        targetHeight: 80,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}
