import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'error_logger.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class FcmService {
  static final _fcm = FirebaseMessaging.instance;
  static final _db = FirebaseFirestore.instance;
  static final _local = FlutterLocalNotificationsPlugin();

  static const _channelId = 'shareit_messages';
  static String get _channelName => 'fcm.channelName'.tr();

  static Future<void> init(String uid) async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    // Το getToken() μπορεί να ρίξει IOException/SERVICE_NOT_AVAILABLE σε κακό
    // δίκτυο ή προβλήματα Play Services — ΔΕΝ πρέπει να κρασάρει την app. Το
    // token θα ξαναζητηθεί αυτόματα (onTokenRefresh) όταν γίνει διαθέσιμο.
    try {
      final token = await _fcm.getToken();
      if (token != null) await _saveToken(uid, token);
    } catch (e, s) {
      logSwallowed(e, s, 'fcm getToken');
    }
    _fcm.onTokenRefresh.listen((t) => _saveToken(uid, t));

    FirebaseMessaging.onMessage.listen(_handleForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

    // Ίδια κατηγορία network-dependent κλήσης στο startup — μη κρασάρεις.
    try {
      final initial = await _fcm.getInitialMessage();
      if (initial != null) _handleOpened(initial);
    } catch (e, s) {
      logSwallowed(e, s, 'fcm getInitialMessage');
    }
  }

  static Future<void> _handleForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['chatId'],
    );
  }

  static void _handleOpened(RemoteMessage message) {
    final chatId = message.data['chatId'];
    final dealId = message.data['dealId'];
    final type = message.data['type'];
    if (navigatorKey.currentContext == null) return;

    if (type == 'message' && chatId != null) {
      navigatorKey.currentState?.pushNamed('/chat/$chatId');
    } else if (type == 'deal_proposal' && chatId != null) {
      navigatorKey.currentState?.pushNamed('/chat/$chatId');
    } else if (type == 'deal_active' && dealId != null) {
      navigatorKey.currentState?.pushNamed('/profile');
    }
  }

  /// Αποθήκευση FCM token — **UPDATE-ONLY**.
  ///
  /// ΚΡΙΣΙΜΟ: ΔΕΝ χρησιμοποιούμε `set(merge:true)`, γιατί αυτό **δημιουργεί** το
  /// user document. Επειδή το [init] τρέχει σε κάθε authStateChanges, ένα
  /// set+merge έφτιαχνε «ghost» docs με μόνο fcmToken (χωρίς όνομα/email) για
  /// κάθε auth event που δεν ολοκλήρωνε profile write — γι' αυτό οι χρήστες
  /// εμφανίζονταν ως «Χρήστης». Με `update()` το write αποτυγχάνει σιωπηλά αν
  /// δεν υπάρχει doc· το token αποθηκεύεται στο επόμενο άνοιγμα.
  static Future<void> _saveToken(String uid, String token) async {
    try {
      await _db.collection('users').doc(uid).update({'fcmToken': token});
    } catch (e, s) {
      logSwallowed(e, s, 'fcm _saveToken (doc missing?)');
    }
  }

  /// Αποθηκεύει τώρα το token — καλείται **αφού** δημιουργηθεί το user document
  /// (εγγραφή / πρώτο Google sign-in). Χρειάζεται γιατί το [init] τρέχει στο
  /// authStateChanges, δηλαδή ΠΡΙΝ γραφτεί το doc, οπότε το update-only write
  /// αποτυγχάνει σιωπηλά για τους ολοκαίνουργιους χρήστες.
  static Future<void> syncToken(String uid) async {
    try {
      final token = await _fcm.getToken();
      if (token != null) await _saveToken(uid, token);
    } catch (e, s) {
      logSwallowed(e, s, 'fcm syncToken');
    }
  }

  /// Αποθηκεύει τη γλώσσα του χρήστη (el/en/es) στο user doc, ώστε οι Cloud
  /// Functions να στέλνουν τα push notifications στη γλώσσα του ΠΑΡΑΛΗΠΤΗ.
  /// Update-only για τον ίδιο λόγο με το [_saveToken].
  static Future<void> saveLanguage(String uid, String lang) async {
    try {
      await _db.collection('users').doc(uid).update({'language': lang});
    } catch (e, s) {
      logSwallowed(e, s, 'fcm saveLanguage (doc missing?)');
    }
  }

  static final navigatorKey = GlobalKey<NavigatorState>();
}
