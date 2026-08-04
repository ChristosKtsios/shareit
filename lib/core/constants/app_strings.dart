import 'package:easy_localization/easy_localization.dart';

/// Κοινά strings της εφαρμογής — localized μέσω easy_localization.
/// Τα κλειδιά ζουν στο assets/translations/{el,en,es}.json.
/// (appName/newListing είναι brand → μένουν σταθερά, όχι μεταφρασμένα.)
class AppStrings {
  AppStrings._();

  static const appName = 'Share your Need';
  static const newListing = 'Share your Need';

  static String get login => 'auth.login'.tr();
  static String get register => 'auth.register'.tr();
  static String get email => 'auth.email'.tr();
  static String get password => 'auth.password'.tr();
  static String get firstName => 'auth.firstName'.tr();
  static String get lastName => 'auth.lastName'.tr();
  static String get phone => 'auth.phone'.tr();
  static String get noAccount => 'auth.noAccount'.tr();
  static String get hasAccount => 'auth.hasAccount'.tr();
  static String get signUp => 'auth.signUp'.tr();

  static String get navMap => 'nav.map'.tr();
  static String get navFeed => 'nav.feed'.tr();
  static String get navMessages => 'nav.messages'.tr();
  static String get navProfile => 'nav.profile'.tr();

  static String get offer => 'listing.offer'.tr();
  static String get seek => 'listing.seek'.tr();
  static String get whatOffer => 'listing.whatOffer'.tr();
  static String get whatSeek => 'listing.whatSeek'.tr();
  static String get description => 'listing.description'.tr();
  static String get availability => 'listing.availability'.tr();
  static String get location => 'listing.location'.tr();
  static String get autoDelete => 'listing.autoDelete'.tr();
  static String get publish => 'listing.publish'.tr();

  static String get messages => 'chat.messages'.tr();
  static String get typeMessage => 'chat.typeMessage'.tr();

  static String get dealClose => 'deal.close'.tr();
  static String get dealActive => 'deal.active'.tr();
  static String get dealDone => 'deal.done'.tr();
  static String get rateUser => 'deal.rateUser'.tr();

  static String get profile => 'profile.title'.tr();
  static String get wall => 'profile.wall'.tr();
  static String get editProfile => 'profile.edit'.tr();
  static String get myListings => 'profile.myListings'.tr();
  static String get activeDeals => 'profile.activeDeals'.tr();

  static String get search => 'search.title'.tr();
  static String get searchHint => 'search.hint'.tr();
  static String get settings => 'settings.title'.tr();
  static String get filters => 'search.filters'.tr();
  static String get applyFilters => 'search.apply'.tr();
  static String get clearFilters => 'search.clear'.tr();

  static String get errorGeneric => 'common.errorGeneric'.tr();
  static String get errorLocation => 'common.errorLocation'.tr();
}
