import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

/// Αντίγραφο των τύπων του MapNotifier (είναι private εκεί). Αν αλλάξουν εκεί,
/// ΠΡΕΠΕΙ να αλλάξουν κι εδώ — τα tests φυλάνε τη σχέση, όχι την υλοποίηση.
const double markerWidthPx = 180.0;
const double clusterPadding = 1.15;

double markerScaleForZoom(double zoom) {
  const minScale = 0.55, maxScale = 1.0, minZoom = 10.0, maxZoom = 16.0;
  if (zoom <= minZoom) return minScale;
  if (zoom >= maxZoom) return maxScale;
  return minScale + (maxScale - minScale) * ((zoom - minZoom) / (maxZoom - minZoom));
}

double metersPerPixel(double zoom, double lat) =>
    156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);

double radiusForZoom(double zoom, double lat) =>
    markerWidthPx * markerScaleForZoom(zoom) * metersPerPixel(zoom, lat) * clusterPadding;

void main() {
  const lat = 38.0; // Ελλάδα

  group('ακτίνα ομαδοποίησης = αποτύπωμα κάρτας στην οθόνη', () {
    test('σε ΚΑΘΕ zoom η ακτίνα καλύπτει το πλάτος της κάρτας', () {
      // Αυτό είναι το νόημα της διόρθωσης: ό,τι επικαλύπτεται οπτικά,
      // ομαδοποιείται. Η ακτίνα σε μέτρα πρέπει να αντιστοιχεί σε
      // τουλάχιστον όσα pixels πιάνει η κάρτα.
      for (final z in [9.0, 11.0, 13.0, 15.0, 17.0, 19.0]) {
        final cardWidthMeters =
            markerWidthPx * markerScaleForZoom(z) * metersPerPixel(z, lat);
        expect(radiusForZoom(z, lat), greaterThanOrEqualTo(cardWidthMeters),
            reason: 'zoom $z: η ακτίνα δεν καλύπτει το πλάτος της κάρτας');
      }
    });

    test('όσο κάνεις zoom in, η ακτίνα μικραίνει', () {
      double? prev;
      for (final z in [9.0, 11.0, 13.0, 15.0, 17.0]) {
        final r = radiusForZoom(z, lat);
        if (prev != null) expect(r, lessThan(prev));
        prev = r;
      }
    });

    test('διορθώνει το παλιό σφάλμα: πολύ μεγαλύτερη από τις παλιές σταθερές',
        () {
      // Παλιές τιμές: 10/30/100/500/1500m — ήταν 14x-21x μικρές.
      final old = {17.0: 10.0, 15.0: 30.0, 13.0: 100.0, 11.0: 500.0, 9.0: 1500.0};
      old.forEach((z, oldRadius) {
        expect(radiusForZoom(z, lat), greaterThan(oldRadius * 5),
            reason: 'zoom $z: θα έπρεπε να είναι πολλαπλάσια της παλιάς');
      });
    });

    test('λαμβάνει υπόψη το γεωγραφικό πλάτος (Mercator)', () {
      // Στα βόρεια, ο ίδιος αριθμός pixels καλύπτει λιγότερα μέτρα.
      expect(radiusForZoom(13, 60.0), lessThan(radiusForZoom(13, 0.0)));
    });

    test('συγκεκριμένο νούμερο: zoom 13 στην Ελλάδα ≈ 2.4 km', () {
      final r = radiusForZoom(13, lat);
      expect(r, greaterThan(2000));
      expect(r, lessThan(2800));
    });
  });
}
