import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class FcmService {
  static final _fcm = FirebaseMessaging.instance;
  static final _db = FirebaseFirestore.instance;
  static final _local = FlutterLocalNotificationsPlugin();

  static const _channelId = 'shareit_messages';
  static const _channelName = 'Μηνύματα ShareIt';

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

    final token = await _fcm.getToken();
    if (token != null) await _saveToken(uid, token);
    _fcm.onTokenRefresh.listen((t) => _saveToken(uid, t));

    FirebaseMessaging.onMessage.listen(_handleForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleOpened(initial);
  }

  static Future<void> _handleForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
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

  /// Αποθήκευση FCM token με set+merge.
  /// Αν το user document δεν υπάρχει ακόμα -> το δημιουργεί με μόνο
  /// το fcmToken. Αν υπάρχει -> ενημερώνει μόνο αυτό το πεδίο.
  static Future<void> _saveToken(String uid, String token) async =>
      await _db.collection('users').doc(uid).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );

  static final navigatorKey = GlobalKey<NavigatorState>();
}
