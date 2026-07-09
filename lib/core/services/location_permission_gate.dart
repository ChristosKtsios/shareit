import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_colors.dart';

/// Root navigator key, used so we can show the location rationale dialog from
/// anywhere — including Riverpod providers that have no [BuildContext].
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Central entry point for obtaining location permission.
///
/// Before the OS permission prompt is shown for the first time we display an
/// in-app rationale explaining *why* the app needs location (Google Play best
/// practice / policy requirement). All location call sites should go through
/// [ensure] instead of calling `Geolocator.requestPermission()` directly.
class LocationPermissionGate {
  LocationPermissionGate._();

  // Shared in-flight future so simultaneous callers (e.g. the map and feed
  // both loading on startup) reuse a single rationale dialog + OS prompt
  // instead of stacking duplicates.
  static Future<LocationPermission>? _inFlight;

  static Future<LocationPermission> ensure() {
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  static Future<LocationPermission> _run() async {
    var perm = await Geolocator.checkPermission();
    // Only `denied` (the not-yet-asked state) triggers the OS prompt; show the
    // rationale right before it. `deniedForever` / granted states are returned
    // as-is so callers can react (the prompt won't appear again anyway).
    if (perm == LocationPermission.denied) {
      final ctx = appNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        // ignore: use_build_context_synchronously
        final proceed = await _showRationale(ctx);
        if (proceed != true) return LocationPermission.denied;
      }
      perm = await Geolocator.requestPermission();
    }
    return perm;
  }

  static Future<bool?> _showRationale(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(children: [
          const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Text('locperm.title'.tr(),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        ]),
        content: Text(
          'locperm.body'.tr(),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('locperm.notNow'.tr(),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('locperm.continue'.tr(),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
