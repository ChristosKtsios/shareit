import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/services/fcm_service.dart';
import 'core/services/presence_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);

  // Background message handler
  FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler);

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

  runApp(const ProviderScope(child: ShareItApp()));
}