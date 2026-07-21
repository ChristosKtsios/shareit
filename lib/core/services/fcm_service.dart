import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'location_permission_gate.dart';
import '../../features/profile/data/user_repository.dart';
import 'error_logger.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class FcmService {
  static final _fcm = FirebaseMessaging.instance;
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

  /// Πλοήγηση όταν ο χρήστης πατήσει την ειδοποίηση.
  ///
  /// Είχε ΔΥΟ σφάλματα και το πάτημα δεν έκανε ποτέ απολύτως τίποτα:
  ///  1. Χρησιμοποιούσε δικό του `navigatorKey`, που ΔΕΝ ήταν συνδεδεμένος με
  ///     κανέναν Navigator (η εφαρμογή χρησιμοποιεί το `appNavigatorKey`).
  ///  2. Έψαχνε τύπους `message`/`deal_proposal`, ενώ ο server στέλνει
  ///     `chat`/`deal`/`post_comment`/`friend_request`. Κανένας δεν ταίριαζε.
  ///
  /// Επίσης χρησιμοποιούσε `pushNamed`, που σε εφαρμογή GoRouter (χωρίς πίνακα
  /// ονομάτων) θα έριχνε εξαίρεση.
  static void _handleOpened(RemoteMessage message) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;

    final type = message.data['type'];
    final chatId = message.data['chatId'];
    final dealId = message.data['dealId'];
    final postId = message.data['postId'];

    switch (type) {
      case 'chat':
        if (chatId != null) ctx.push('/chat/$chatId');
        break;
      case 'deal':
        if (dealId != null) ctx.push('/deal-review/$dealId');
        break;
      case 'post_comment':
        if (postId != null) ctx.push('/user-post/$postId');
        break;
      case 'friend_request':
        ctx.push('/friend-requests');
        break;
    }
  }

  /// Αποθήκευση FCM token στο **private** doc (`users/{uid}/private/data`).
  ///
  /// Το token είναι αναγνωριστικό συσκευής: αν έμενε στο δημόσιο user doc, θα
  /// το κατέβαζε κάθε χρήστης που βλέπει το προφίλ. Το private doc διαβάζεται
  /// μόνο από τον ίδιο (rules) και από τις Cloud Functions (admin).
  ///
  /// Το `set(merge)` εδώ είναι ασφαλές: γράφει σε **subcollection**, οπότε ΔΕΝ
  /// δημιουργεί το `users/{uid}` — δεν επιστρέφουν τα «ghost» user docs που
  /// εμφάνιζαν χρήστες ως «Χρήστης».
  static Future<void> _saveToken(String uid, String token) async {
    try {
      await UserRepository.privateRef(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
    } catch (e, s) {
      logSwallowed(e, s, 'fcm _saveToken');
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

  /// Αποθηκεύει τη γλώσσα του χρήστη (el/en/es) στο private doc, ώστε οι Cloud
  /// Functions να στέλνουν τα push notifications στη γλώσσα του ΠΑΡΑΛΗΠΤΗ.
  static Future<void> saveLanguage(String uid, String lang) async {
    try {
      await UserRepository.privateRef(uid)
          .set({'language': lang}, SetOptions(merge: true));
    } catch (e, s) {
      logSwallowed(e, s, 'fcm saveLanguage');
    }
  }
}
