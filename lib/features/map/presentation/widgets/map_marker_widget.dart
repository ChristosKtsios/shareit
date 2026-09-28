import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../../features/listings/data/listing_model.dart';
import 'marker_image_cache.dart';
import 'user_map_cache.dart';

/// «Photo-forward pin»: μια μεγάλη στρογγυλεμένη φωτογραφία (η βασική οπτική
/// ταυτότητα, όπως τα pins του Airbnb) αντί για μικρά thumbnails δίπλα σε
/// κείμενο. Ο τύπος (badge πάνω-αριστερά) και ο χρήστης (avatar κάτω-δεξιά)
/// γίνονται μικρά «μενταγιόν» πάνω στις γωνίες της φωτογραφίας, και ο τίτλος
/// επικάθεται στο κάτω μέρος της φωτογραφίας με σκίαση για ευκρίνεια — έτσι
/// τραβάει περισσότερο το μάτι απ' ό,τι μια κάρτα γεμάτη κείμενο.
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
    final userInfo = await UserMapCache.get(listing.userId);
    final displayInitial = (userInfo != null && userInfo.initial != '?')
        ? userInfo.initial
        : (listing.userFirstName.isNotEmpty
            ? listing.userFirstName[0].toUpperCase()
            : '?');
    final avatarUrl = userInfo?.avatarUrl ?? listing.userAvatarUrl;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final photoSize = 88.0 * scale;
    final width = photoSize + 16 * scale;
    final tailHeight = 12.0 * scale;
    final height = photoSize + 10 * scale + tailHeight;

    final photoRect =
        Rect.fromLTWH((width - photoSize) / 2, 2 * scale, photoSize, photoSize);
    final photoRRect =
        RRect.fromRectAndRadius(photoRect, Radius.circular(22 * scale));

    // ── Σκιά κάτω από τη φωτογραφία (δίνει βάθος, «ξεκολλάει» από τον χάρτη) ──
    canvas.drawRRect(
      photoRRect.shift(Offset(0, 3 * scale)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale),
    );

    // ── Η φωτογραφία (ή έγχρωμο gradient fallback με emoji αν δεν υπάρχει) ──
    final photoUrl = listing.imageUrls.isNotEmpty ? listing.imageUrls.first : null;
    final photoImage = photoUrl != null ? await MarkerImageCache.load(photoUrl) : null;

    canvas.save();
    canvas.clipRRect(photoRRect);
    if (photoImage != null) {
      final srcSize =
          photoImage.width < photoImage.height ? photoImage.width : photoImage.height;
      final srcX = (photoImage.width - srcSize) / 2;
      final srcY = (photoImage.height - srcSize) / 2;
      canvas.drawImageRect(
        photoImage,
        Rect.fromLTWH(srcX.toDouble(), srcY.toDouble(), srcSize.toDouble(),
            srcSize.toDouble()),
        photoRect,
        Paint(),
      );
    } else {
      final gradient = ui.Gradient.linear(
        photoRect.topLeft,
        photoRect.bottomRight,
        [color.withValues(alpha: 0.55), color.withValues(alpha: 0.85)],
      );
      canvas.drawRect(photoRect, Paint()..shader = gradient);
      final bigEmojiPainter = TextPainter(
        text: TextSpan(text: emoji, style: TextStyle(fontSize: 34 * scale)),
        textDirection: TextDirection.ltr,
      )..layout();
      bigEmojiPainter.paint(
        canvas,
        Offset(photoRect.center.dx - bigEmojiPainter.width / 2,
            photoRect.center.dy - bigEmojiPainter.height / 2),
      );
    }

    // ── Σκίαση κάτω μέρους (gradient scrim) ώστε ο τίτλος να διαβάζεται ──
    final scrimRect = Rect.fromLTWH(
        photoRect.left, photoRect.bottom - 30 * scale, photoSize, 30 * scale);
    canvas.drawRect(
      scrimRect,
      Paint()
        ..shader = ui.Gradient.linear(
          scrimRect.topCenter,
          scrimRect.bottomCenter,
          [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.75)],
        ),
    );
    canvas.restore();

    // Χρωματιστό περίγραμμα γύρω από τη φωτογραφία (δηλώνει τον τύπο)
    canvas.drawRRect(
      photoRRect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * scale,
    );

    // ── Τίτλος αγγελίας, πάνω στη σκίαση ──
    const maxTitleLen = 16;
    final shortTitle = listing.title.length > maxTitleLen
        ? '${listing.title.substring(0, maxTitleLen)}…'
        : listing.title;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: shortTitle,
        style: TextStyle(
            color: Colors.white, fontSize: 11 * scale, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
    )..layout(maxWidth: photoSize - 10 * scale);
    titlePainter.paint(
      canvas,
      Offset(photoRect.center.dx - titlePainter.width / 2,
          photoRect.bottom - titlePainter.height - 5 * scale),
    );

    // ── Badge τύπου (emoji), «μενταγιόν» πάνω-αριστερά στη γωνία της φωτό ──
    final typeBadgeCenter = photoRect.topLeft;
    final typeBadgeRadius = 15.0 * scale;
    canvas.drawCircle(typeBadgeCenter, typeBadgeRadius, Paint()..color = color);
    canvas.drawCircle(
      typeBadgeCenter,
      typeBadgeRadius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale,
    );
    final emojiPainter = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: 14 * scale)),
      textDirection: TextDirection.ltr,
    )..layout();
    emojiPainter.paint(
      canvas,
      Offset(typeBadgeCenter.dx - emojiPainter.width / 2,
          typeBadgeCenter.dy - emojiPainter.height / 2),
    );

    // ── Avatar χρήστη, «μενταγιόν» κάτω-δεξιά στη γωνία της φωτό ──
    final avatarCenter = photoRect.bottomRight;
    final avatarRadius = 15.0 * scale;
    ui.Image? avatarImage;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarImage = await MarkerImageCache.load(avatarUrl);
    }
    canvas.drawCircle(avatarCenter, avatarRadius, Paint()..color = Colors.white);
    if (avatarImage != null) {
      canvas.save();
      final clip = Path()
        ..addOval(Rect.fromCircle(
            center: avatarCenter, radius: avatarRadius - 2 * scale));
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
        Rect.fromCircle(center: avatarCenter, radius: avatarRadius - 2 * scale),
        Paint(),
      );
      canvas.restore();
    } else {
      canvas.drawCircle(avatarCenter, avatarRadius - 2 * scale,
          Paint()..color = color.withValues(alpha: 0.85));
      final initialPainter = TextPainter(
        text: TextSpan(
            text: displayInitial,
            style: TextStyle(
                color: Colors.white,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      initialPainter.paint(
          canvas,
          Offset(avatarCenter.dx - initialPainter.width / 2,
              avatarCenter.dy - initialPainter.height / 2));
    }

    // ── Ουρά (δείχνει το ακριβές σημείο στον χάρτη) ──
    final tailPath = Path()
      ..moveTo(width / 2 - 8 * scale, photoRect.bottom + 4 * scale)
      ..lineTo(width / 2 + 8 * scale, photoRect.bottom + 4 * scale)
      ..lineTo(width / 2, height)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = color);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), height.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }
}
