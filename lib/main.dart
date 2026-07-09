import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/services/fcm_service.dart';
import 'core/services/presence_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await EasyLocalization.ensureInitialized();
    // Αρχικοποίηση intl date symbols ώστε το DateFormat να δίνει μήνες/ημερομηνίες
    // στη σωστή γλώσσα (el/en/es) — locale-aware μορφοποίηση ημερομηνιών.
    await initializeDateFormatting();
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    // App Check — μπλοκάρει κλήσεις σε Cloud Functions/Firestore/Storage από
    // μη-γνήσια clients (π.χ. script που καλεί απευθείας το checkAccountExists /
    // getEmailByPhone για enumeration).
    // Σε debug χρησιμοποιούμε debug provider (αλλιώς το `flutter run` μπλοκάρεται)·
    // σε release Play Integrity (Android) και App Attest (iOS).
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );

    // Crashlytics setup
    // Σε debug mode τα crashes δεν στέλνονται για να μη σπαμάρουμε το dashboard
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Offline mode — Firestore cache
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Presence service — ξεκινά μόλις γίνει login
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        PresenceService().start();
      } else {
        PresenceService().stop();
      }
    });

    runApp(
      EasyLocalization(
        // Default = γλώσσα συσκευής αν είναι el/en/es, αλλιώς fallback Αγγλικά.
        supportedLocales: const [Locale('el'), Locale('en'), Locale('es')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: const ProviderScope(child: ShareItApp()),
      ),
    );
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}
