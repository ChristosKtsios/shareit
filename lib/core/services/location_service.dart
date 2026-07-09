import 'package:geolocator/geolocator.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'location_permission_gate.dart';

class LocationService {
  static Future<Position?> getCurrentPosition() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return null;
      final perm = await LocationPermissionGate.ensure();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
    } catch (_) { return null; }
  }
  static GeoPoint toGeoPoint(Position p) => GeoPoint(p.latitude, p.longitude);
  static double distanceMeters(GeoPoint a, GeoPoint b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
  static String formatDistance(double m) =>
      m < 1000 ? '${m.round()}${'map.unitM'.tr()}' : '${(m / 1000).toStringAsFixed(1)}${'map.unitKm'.tr()}';

  /// Μετατρέπει συντεταγμένες σε ανθρώπινη διεύθυνση (π.χ. "Δωδώνης, Ιωάννινα")
  /// μέσω του native geocoder της συσκευής — δεν χρειάζεται API key/χρέωση.
  /// Επιστρέφει null αν αποτύχει ή δεν βρεθεί κάτι χρήσιμο.
  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return null;
      final p = marks.first;
      // Προτιμάμε "οδός, πόλη"· πέφτουμε σε ό,τι υπάρχει διαθέσιμο.
      final street = (p.thoroughfare ?? '').trim();
      final area = (p.locality ?? '').trim().isNotEmpty
          ? p.locality!.trim()
          : (p.subAdministrativeArea ?? '').trim();
      final parts = [
        if (street.isNotEmpty) street,
        if (area.isNotEmpty) area,
      ];
      if (parts.isNotEmpty) return parts.join(', ');
      final fallback = (p.administrativeArea ?? p.country ?? '').trim();
      return fallback.isEmpty ? null : fallback;
    } catch (_) {
      return null;
    }
  }
}
