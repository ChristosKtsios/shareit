import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationService {
  static Future<Position?> getCurrentPosition() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (_) { return null; }
  }
  static GeoPoint toGeoPoint(Position p) => GeoPoint(p.latitude, p.longitude);
  static double distanceMeters(GeoPoint a, GeoPoint b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
  static String formatDistance(double m) =>
      m < 1000 ? '${m.round()}μ' : '${(m / 1000).toStringAsFixed(1)}χλμ';
}
