import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Εικόνα από δίκτυο που **ποτέ δεν δείχνει σφάλμα στον χρήστη**.
///
/// Γιατί υπάρχει: το σκέτο `Image.network` χωρίς `errorBuilder` εμφανίζει το
/// ίδιο το exception μέσα στο layout — ο χρήστης έβλεπε κόκκινο κείμενο τύπου
/// «SocketException: Failed host lookup: firebasestorage…» πάνω στην κάρτα της
/// αγγελίας. Αυτό συμβαίνει σε κάθε προσωρινή απώλεια δικτύου.
///
/// Εδώ, αποτυχία = διακριτικό εικονίδιο. Ο χρήστης καταλαβαίνει ότι λείπει η
/// εικόνα, χωρίς να νομίζει ότι η εφαρμογή χάλασε.
class SafeNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Μέγεθος του εικονιδίου σφάλματος. Αν δεν δοθεί, υπολογίζεται από το
  /// μέγεθος της εικόνας.
  final double? iconSize;

  const SafeNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(Icons.broken_image_outlined),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder(null);
      },
    );
  }

  Widget _placeholder(IconData? icon) {
    final size = iconSize ??
        (width != null && width! < 80 ? 20.0 : 32.0);
    return Container(
      width: width,
      height: height,
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: icon == null
          ? SizedBox(
              width: size * 0.6,
              height: size * 0.6,
              child: const CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.textHint),
            )
          : Icon(icon, size: size, color: AppColors.textHint),
    );
  }
}
