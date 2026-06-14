import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Κοινός loader/cache για network images που σχεδιάζονται σε canvas
/// (markers & clusters). Χρησιμοποιεί NetworkImage.resolve — αξιόπιστο
/// με Firebase Storage URLs (tokens), σε αντίθεση με το NetworkAssetBundle
/// που αποτύγχανε σιωπηλά κι έδειχνε placeholder αντί για τη φωτογραφία.
///
/// Κρατάει cache από decoded ui.Image ώστε τα markers να ΜΗΝ ξανακατεβάζουν
/// τις ίδιες φωτογραφίες σε κάθε zoom rebuild (απόδοση).
class MarkerImageCache {
  MarkerImageCache._();

  static final Map<String, ui.Image> _cache = {};

  /// Επιστρέφει decoded ui.Image από URL (cached). null αν αποτύχει.
  static Future<ui.Image?> load(String url) async {
    final cached = _cache[url];
    if (cached != null) return cached;

    try {
      final image = await _fetchAndDecode(url);
      if (image != null) _cache[url] = image;
      return image;
    } catch (e) {
      debugPrint('MarkerImageCache: failed to load $url -> $e');
      return null;
    }
  }

  static Future<ui.Image?> _fetchAndDecode(String url) {
    final provider = NetworkImage(url);
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(const ImageConfiguration());

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? _) {
        if (!completer.isCompleted) completer.complete(null);
        stream.removeListener(listener);
      },
    );

    stream.addListener(listener);
    return completer.future;
  }

  static void clear() => _cache.clear();
}
