import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/services/auth_consent_gate.dart';
import 'core/services/fcm_service.dart';
import 'core/services/location_permission_gate.dart';
import 'core/services/profile_gate.dart';
import 'features/auth/presentation/complete_profile_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/register_screen.dart';
import 'features/auth/presentation/forgot_password_screen.dart';
import 'features/auth/presentation/phone_auth_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/map/presentation/map_screen.dart';
import 'features/feed/presentation/feed_screen.dart';
import 'features/listings/presentation/create_listing_screen.dart';
import 'features/listings/presentation/edit_listing_screen.dart';
import 'features/listings/presentation/listing_detail_screen.dart';
import 'features/listings/presentation/my_listings_screen.dart';
import 'features/listings/presentation/user_listings_screen.dart';
import 'features/chat/presentation/chat_screen.dart';
import 'features/chat/presentation/inbox_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/profile/presentation/edit_profile_screen.dart';
import 'features/profile/presentation/create_user_post_screen.dart';
import 'features/profile/presentation/user_posts_screen.dart';
import 'features/profile/presentation/user_post_detail_screen.dart';
import 'features/profile/presentation/profile_photos_screen.dart';
import 'features/profile/presentation/delete_account_screen.dart';
import 'features/profile/presentation/friend_requests_screen.dart';
import 'features/profile/presentation/friends_list_screen.dart';
import 'features/search/presentation/search_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/settings/presentation/change_password_screen.dart';
import 'features/profile/presentation/change_phone_screen.dart';
import 'features/profile/presentation/change_email_screen.dart';
import 'features/settings/presentation/blocked_users_screen.dart';
import 'features/settings/presentation/notification_settings_screen.dart';
import 'features/settings/presentation/help_support_screen.dart';
import 'features/notifications/presentation/notifications_screen.dart';
import 'features/deals/presentation/rate_user_screen.dart';
import 'features/deals/presentation/rate_deal_screen.dart';
import 'features/deals/presentation/deal_proposal_screen.dart';
import 'features/deals/presentation/deal_review_screen.dart';
import 'features/deals/presentation/my_deals_screen.dart';
import 'features/report/presentation/report_screen.dart';
import 'features/saved/presentation/saved_screen.dart';
import 'features/listings/presentation/listing_images_screen.dart';
import 'features/profile/presentation/wall_post_detail_screen.dart';
import 'features/shell/presentation/main_shell.dart';

/// Ειδοποιεί τον router σε κάθε αλλαγή auth ΧΩΡΙΣ να ξαναχτίζεται ολόκληρος ο
/// GoRouter — ξανατρέχει μόνο το redirect. (Αποφεύγουμε navigation resets /
/// διπλό navigatorKey που προκαλούσε το ref.watch rebuild.)
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<User?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<User?> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(FirebaseAuth.instance.authStateChanges());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/map',
    refreshListenable: refresh,
    redirect: (context, state) async {
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' ||
          loc == '/register' ||
          loc == '/onboarding' ||
          loc == '/forgot-password' ||
          loc == '/phone-auth';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) {
        // Νέος χρήστης Google σε αποδοχή όρων/18+: ΜΕΙΝΕ στην οθόνη login μέχρι
        // να αποδεχτεί (ή να ακυρωθεί). Το `signInWithCredential` πυροδοτεί
        // authStateChanges πριν προλάβει να δειχτεί ο διάλογος συναίνεσης· χωρίς
        // αυτό, ο router έφευγε στο /map και ο χρήστης μπαινε ΧΩΡΙΣ αποδοχή.
        if (AuthConsentGate.pending) return null;
        return '/map';
      }

      if (loc == '/login') {
        final prefs = await SharedPreferences.getInstance();
        final done = prefs.getBool(AppConstants.onboardingKey) ?? false;
        if (!done) return '/onboarding';
      }

      // ── Gate: το ΜΟΝΟ υποχρεωτικό βήμα είναι το όνομα ──
      // Η επαλήθευση κινητού ΔΕΝ είναι πλέον υποχρεωτική: ήταν, αλλά σήμαινε
      // ότι ένα SMS που δεν έφτανε άφηνε τον χρήστη κλειδωμένο έξω χωρίς καμία
      // εναλλακτική. Όποιος δεν έχει επαληθευμένο κινητό μπαίνει κανονικά και
      // εμφανίζεται ως «Μη επαληθευμένος χρήστης» στο προφίλ του.
      // Cached ανά uid (1 read/session). Σε σφάλμα → none, δεν μπλοκάρει.
      if (isLoggedIn) {
        final step = await ProfileGate.nextStep();

        if (step == ProfileGateStep.completeProfile) {
          if (loc != '/complete-profile') return '/complete-profile';
        } else if (loc == '/complete-profile') {
          return '/map';
        }
      }
      return null;
    },
    routes: [
      // Auth
      GoRoute(
          path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/complete-profile',
          builder: (_, __) => const CompleteProfileScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/phone-auth',
        builder: (_, state) => PhoneAuthScreen(
          registerData: state.extra as Map<String, dynamic>?,
        ),
      ),
      // Main shell
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
          GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
          GoRoute(path: '/messages', builder: (_, __) => const InboxScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
      // Listings
      GoRoute(
          path: '/listing/new',
          builder: (_, __) => const CreateListingScreen()),
      GoRoute(
          path: '/edit-listing/:id',
          builder: (_, s) =>
              EditListingScreen(listingId: s.pathParameters['id']!)),
      GoRoute(
          path: '/listing/:id',
          builder: (_, s) =>
              ListingDetailScreen(listingId: s.pathParameters['id']!)),
      GoRoute(
          path: '/my-listings', builder: (_, __) => const MyListingsScreen()),
      // Οι αγγελίες ΕΝΟΣ χρήστη («ShareIt» κουτί στο προφίλ). Ο έλεγχος
      // ιδιωτικότητας γίνεται μέσα στην οθόνη, όχι εδώ.
      GoRoute(
          path: '/user-listings/:uid',
          builder: (_, state) =>
              UserListingsScreen(uid: state.pathParameters['uid']!)),
      // Chat
      GoRoute(
          path: '/chat/:chatId',
          builder: (_, s) => ChatScreen(chatId: s.pathParameters['chatId']!)),
      // Profile
      //
      // ΚΡΙΣΙΜΗ ΣΕΙΡΑ: το go_router ταιριάζει τις διαδρομές με τη σειρά που
      // δηλώνονται. Αν το `/profile/:uid` μπει ΠΡΩΤΟ, καταπίνει και το
      // `/profile/photos` και το `/profile/edit` — δηλαδή το «Προσθήκη
      // φωτογραφίας» άνοιγε το προφίλ ενός ανύπαρκτου χρήστη με uid "photos".
      // Οι σταθερές διαδρομές ΠΑΝΤΑ πριν από την παραμετρική.
      GoRoute(
          path: '/profile/edit', builder: (_, __) => const EditProfileScreen()),
      GoRoute(
          path: '/profile/photos',
          builder: (_, __) => const ProfilePhotosScreen()),
      GoRoute(
          path: '/profile/:uid',
          builder: (_, s) => ProfileScreen(userId: s.pathParameters['uid'])),
      GoRoute(
          path: '/delete-account',
          builder: (_, __) => const DeleteAccountScreen()),
      // Friend requests + Friends list
      GoRoute(
          path: '/friend-requests',
          builder: (_, __) => const FriendRequestsScreen()),
      GoRoute(path: '/friends', builder: (_, __) => const FriendsListScreen()),
      // Search
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      // Settings
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
          path: '/settings/edit-profile',
          builder: (_, __) => const EditProfileScreen()),
      GoRoute(
          path: '/create-post',
          builder: (_, __) => const CreateUserPostScreen()),
      GoRoute(
          path: '/user-posts/:uid',
          builder: (_, state) =>
              UserPostsScreen(uid: state.pathParameters['uid']!)),
      GoRoute(
          path: '/user-post/:postId',
          builder: (_, state) =>
              UserPostDetailScreen(postId: state.pathParameters['postId']!)),
      GoRoute(
          path: '/settings/change-password',
          builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(
          path: '/settings/change-phone',
          builder: (_, __) => const ChangePhoneScreen()),
      GoRoute(
          path: '/settings/change-email',
          builder: (_, __) => const ChangeEmailScreen()),
      GoRoute(
          path: '/settings/blocked',
          builder: (_, __) => const BlockedUsersScreen()),
      GoRoute(
          path: '/settings/notifications',
          builder: (_, __) => const NotificationSettingsScreen()),
      GoRoute(
          path: '/settings/help',
          builder: (_, __) => const HelpSupportScreen()),
      // Notifications
      GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen()),
      // Deals
      GoRoute(
          path: '/rate/:dealId',
          builder: (_, s) => RateUserScreen(
                dealId: s.pathParameters['dealId']!,
                targetName: s.uri.queryParameters['name'] ?? '',
                targetInitials: s.uri.queryParameters['initials'] ?? '?',
              )),
      GoRoute(
          path: '/rate-deal/:dealId',
          builder: (_, s) =>
              RateDealScreen(dealId: s.pathParameters['dealId']!)),
      GoRoute(
          path: '/deal-proposal/:chatId',
          builder: (_, s) => DealProposalScreen(
                chatId: s.pathParameters['chatId']!,
                listingId: s.uri.queryParameters['listingId'] ?? '',
                listingTitle: s.uri.queryParameters['listingTitle'] ?? '',
                otherUserUid: s.uri.queryParameters['otherUserUid'] ?? '',
                existingDealId: s.uri.queryParameters['dealId'],
              )),
      // Deal review (full-screen με Αποδοχή/Απόρριψη)
      GoRoute(
          path: '/deal-review/:dealId',
          builder: (_, s) => DealReviewScreen(
                dealId: s.pathParameters['dealId']!,
              )),
      // Τα Deals μου (3 tabs)
      GoRoute(path: '/my-deals', builder: (_, __) => const MyDealsScreen()),
      // Report
      GoRoute(
          path: '/report/user/:uid',
          builder: (_, s) => ReportScreen(targetUid: s.pathParameters['uid']!)),
      GoRoute(
          path: '/report/listing/:uid/:listingId',
          builder: (_, s) => ReportScreen(
                targetUid: s.pathParameters['uid']!,
                listingId: s.pathParameters['listingId'],
              )),
      GoRoute(
          path: '/report/message/:uid/:chatId/:messageId',
          builder: (_, s) => ReportScreen(
                targetUid: s.pathParameters['uid']!,
                chatId: s.pathParameters['chatId'],
                messageId: s.pathParameters['messageId'],
              )),
      // Αναφορά περιεχομένου: post (wallPosts/userPosts) και σχόλιο σε post.
      GoRoute(
          path: '/report/post/:uid/:col/:postId',
          builder: (_, s) => ReportScreen(
                targetUid: s.pathParameters['uid']!,
                postCollection: s.pathParameters['col'],
                postId: s.pathParameters['postId'],
              )),
      GoRoute(
          path: '/report/comment/:uid/:col/:postId/:commentId',
          builder: (_, s) => ReportScreen(
                targetUid: s.pathParameters['uid']!,
                postCollection: s.pathParameters['col'],
                postId: s.pathParameters['postId'],
                commentId: s.pathParameters['commentId'],
              )),
      // Saved
      GoRoute(path: '/saved', builder: (_, __) => const SavedScreen()),
      // Listing images
      GoRoute(
          path: '/listing/:id/images',
          builder: (_, s) {
            final raw = s.extra;
            final urls = raw is List
                ? raw.map((e) => e.toString()).toList()
                : <String>[];
            return ListingImagesScreen(
              imageUrls: urls,
              initialIndex:
                  int.tryParse(s.uri.queryParameters['i'] ?? '0') ?? 0,
            );
          }),
      // Wall post
      GoRoute(
          path: '/wall-post/:postId',
          builder: (_, s) =>
              WallPostDetailScreen(postId: s.pathParameters['postId']!)),
    ],
  );
});

/// Ο τελευταίος χρήστης του οποίου συγχρονίστηκε η γλώσσα στο Firestore (μία
/// φορά ανά χρήστη/εκκίνηση) — για locale-aware push από τις Cloud Functions.
String? _langSyncedUid;

class ShareItApp extends ConsumerWidget {
  const ShareItApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid != _langSyncedUid) {
      _langSyncedUid = uid;
      final lang = context.locale.languageCode;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => FcmService.saveLanguage(uid, lang));
    }
    return MaterialApp.router(
      title: 'ShareIt',
      theme: AppTheme.dark,
      routerConfig: ref.watch(_routerProvider),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}
