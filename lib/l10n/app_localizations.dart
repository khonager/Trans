import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'Trans'**
  String get appTitle;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @resetPasswordMessage.
  ///
  /// In en, this message translates to:
  /// **'You have securely logged in via the password reset link. Please set a new password now.'**
  String get resetPasswordMessage;

  /// No description provided for @resetPasswordSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Tap the \'Edit\' icon in your profile to set a new password.'**
  String get resetPasswordSnackbar;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @quitAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Quit App?'**
  String get quitAppTitle;

  /// No description provided for @quitAppMessage.
  ///
  /// In en, this message translates to:
  /// **'Do you want to exit the application?'**
  String get quitAppMessage;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @routes.
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get routes;

  /// No description provided for @friends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friends;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @changelogTitle.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get changelogTitle;

  /// No description provided for @failedToLoadReleases.
  ///
  /// In en, this message translates to:
  /// **'Failed to load releases: {statusCode}'**
  String failedToLoadReleases(String statusCode);

  /// No description provided for @errorLoadingReleases.
  ///
  /// In en, this message translates to:
  /// **'Error loading releases: {error}'**
  String errorLoadingReleases(String error);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @unknownVersion.
  ///
  /// In en, this message translates to:
  /// **'Unknown Version'**
  String get unknownVersion;

  /// No description provided for @noDescription.
  ///
  /// In en, this message translates to:
  /// **'No description.'**
  String get noDescription;

  /// No description provided for @currentVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'{tagName} (Current)'**
  String currentVersionLabel(String tagName);

  /// No description provided for @addNewFriend.
  ///
  /// In en, this message translates to:
  /// **'Add New Friend'**
  String get addNewFriend;

  /// No description provided for @searchByUsername.
  ///
  /// In en, this message translates to:
  /// **'Search by username...'**
  String get searchByUsername;

  /// No description provided for @requestSentTo.
  ///
  /// In en, this message translates to:
  /// **'Request sent to @{username}'**
  String requestSentTo(String username);

  /// No description provided for @friendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friendsTitle;

  /// No description provided for @activeNow.
  ///
  /// In en, this message translates to:
  /// **'Active Now'**
  String get activeNow;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @noFriendsYet.
  ///
  /// In en, this message translates to:
  /// **'No friends yet.'**
  String get noFriendsYet;

  /// No description provided for @sentFriendRequest.
  ///
  /// In en, this message translates to:
  /// **'Sent a friend request'**
  String get sentFriendRequest;

  /// No description provided for @friendRequestAccepted.
  ///
  /// In en, this message translates to:
  /// **'Friend request accepted!'**
  String get friendRequestAccepted;

  /// No description provided for @friendRequestDenied.
  ///
  /// In en, this message translates to:
  /// **'Friend request denied.'**
  String get friendRequestDenied;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @activeRecently.
  ///
  /// In en, this message translates to:
  /// **'Active recently'**
  String get activeRecently;

  /// No description provided for @onLine.
  ///
  /// In en, this message translates to:
  /// **'On {line}'**
  String onLine(String line);

  /// No description provided for @lastOnLine.
  ///
  /// In en, this message translates to:
  /// **'Last on {line}'**
  String lastOnLine(String line);

  /// No description provided for @activeRecentlyGhost.
  ///
  /// In en, this message translates to:
  /// **'Active recently (Ghost)'**
  String get activeRecentlyGhost;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @removeFriendTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {username}?'**
  String removeFriendTitle(String username);

  /// No description provided for @removeFriendMessage.
  ///
  /// In en, this message translates to:
  /// **'They will be removed from your friends list.'**
  String get removeFriendMessage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @removedFriend.
  ///
  /// In en, this message translates to:
  /// **'Removed {username}'**
  String removedFriend(String username);

  /// No description provided for @blockedFriend.
  ///
  /// In en, this message translates to:
  /// **'Blocked {username}'**
  String blockedFriend(String username);

  /// No description provided for @errorString.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorString(String error);

  /// No description provided for @routesFound.
  ///
  /// In en, this message translates to:
  /// **'{count} Routes Found'**
  String routesFound(String count);

  /// No description provided for @earliestDep.
  ///
  /// In en, this message translates to:
  /// **'Earliest Dep.'**
  String get earliestDep;

  /// No description provided for @earliestArr.
  ///
  /// In en, this message translates to:
  /// **'Earliest Arr.'**
  String get earliestArr;

  /// No description provided for @fastest.
  ///
  /// In en, this message translates to:
  /// **'Fastest'**
  String get fastest;

  /// No description provided for @leastTransfers.
  ///
  /// In en, this message translates to:
  /// **'Least Transfers'**
  String get leastTransfers;

  /// No description provided for @leastWait.
  ///
  /// In en, this message translates to:
  /// **'Least Wait'**
  String get leastWait;

  /// No description provided for @leastWalking.
  ///
  /// In en, this message translates to:
  /// **'Least Walking'**
  String get leastWalking;

  /// No description provided for @loadEarlier.
  ///
  /// In en, this message translates to:
  /// **'Load Earlier'**
  String get loadEarlier;

  /// No description provided for @loadLater.
  ///
  /// In en, this message translates to:
  /// **'Load Later'**
  String get loadLater;

  /// No description provided for @routeTicketCopied.
  ///
  /// In en, this message translates to:
  /// **'Route ticket copied to clipboard!'**
  String get routeTicketCopied;

  /// No description provided for @failedToCopy.
  ///
  /// In en, this message translates to:
  /// **'Failed to copy: {error}'**
  String failedToCopy(String error);

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'CANCELLED'**
  String get cancelled;

  /// No description provided for @transfersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} transfers'**
  String transfersCount(String count);

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied. Alarm cannot work.'**
  String get locationPermissionDenied;

  /// No description provided for @locationPermissionPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission permanently denied.'**
  String get locationPermissionPermanentlyDenied;

  /// No description provided for @missingDestCoords.
  ///
  /// In en, this message translates to:
  /// **'Cannot start alarm: Missing destination coordinates.'**
  String get missingDestCoords;

  /// No description provided for @wakeUpApproaching.
  ///
  /// In en, this message translates to:
  /// **'Wake Up! Approaching {stop}!'**
  String wakeUpApproaching(String stop);

  /// No description provided for @serviceBusyTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Service temporarily busy. Try again or type more characters.'**
  String get serviceBusyTryAgain;

  /// No description provided for @serviceBusyPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Service temporarily busy. Please try again.'**
  String get serviceBusyPleaseTryAgain;

  /// No description provided for @locationNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Location not available.'**
  String get locationNotAvailable;

  /// No description provided for @noRoutesFound.
  ///
  /// In en, this message translates to:
  /// **'No routes found.'**
  String get noRoutesFound;

  /// No description provided for @noRoutesFoundBusy.
  ///
  /// In en, this message translates to:
  /// **'No routes found. The service may be temporarily busy - please try again.'**
  String get noRoutesFoundBusy;

  /// No description provided for @requestTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Request timed out. Please try again.'**
  String get requestTimedOut;

  /// No description provided for @serviceBusyMoment.
  ///
  /// In en, this message translates to:
  /// **'Service temporarily busy. Please try again in a moment.'**
  String get serviceBusyMoment;

  /// No description provided for @weakGps.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Weak GPS'**
  String get weakGps;

  /// No description provided for @planJourney.
  ///
  /// In en, this message translates to:
  /// **'Plan Journey'**
  String get planJourney;

  /// No description provided for @tripTime.
  ///
  /// In en, this message translates to:
  /// **'Trip Time'**
  String get tripTime;

  /// No description provided for @now.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get now;

  /// No description provided for @currentLocation.
  ///
  /// In en, this message translates to:
  /// **'Current Location'**
  String get currentLocation;

  /// No description provided for @fromStationOrAddress.
  ///
  /// In en, this message translates to:
  /// **'Start station or address...'**
  String get fromStationOrAddress;

  /// No description provided for @toStationOrAddress.
  ///
  /// In en, this message translates to:
  /// **'Destination station or address...'**
  String get toStationOrAddress;

  /// No description provided for @stationOrAddress.
  ///
  /// In en, this message translates to:
  /// **'Station or Address...'**
  String get stationOrAddress;

  /// No description provided for @fromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fromLabel;

  /// No description provided for @toLabel.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get toLabel;

  /// No description provided for @arriveBy.
  ///
  /// In en, this message translates to:
  /// **'Arrive by'**
  String get arriveBy;

  /// No description provided for @departAt.
  ///
  /// In en, this message translates to:
  /// **'Depart at'**
  String get departAt;

  /// No description provided for @refreshLocation.
  ///
  /// In en, this message translates to:
  /// **'Refresh location'**
  String get refreshLocation;

  /// No description provided for @findRoutes.
  ///
  /// In en, this message translates to:
  /// **'Find Routes'**
  String get findRoutes;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @frequentJourneys.
  ///
  /// In en, this message translates to:
  /// **'Frequent Journeys'**
  String get frequentJourneys;

  /// No description provided for @fromStation.
  ///
  /// In en, this message translates to:
  /// **'From {station}'**
  String fromStation(String station);

  /// No description provided for @couldNotLoadMoreRoutes.
  ///
  /// In en, this message translates to:
  /// **'Could not load more routes: {error}'**
  String couldNotLoadMoreRoutes(String error);

  /// No description provided for @couldNotRefreshRoutes.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh routes: {error}'**
  String couldNotRefreshRoutes(String error);

  /// No description provided for @refreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed: {error}'**
  String refreshFailed(String error);

  /// No description provided for @cancelledL10n.
  ///
  /// In en, this message translates to:
  /// **' CANCELLED'**
  String get cancelledL10n;

  /// No description provided for @boardAtPlatform.
  ///
  /// In en, this message translates to:
  /// **'Board at {station} (Pl. {platform})'**
  String boardAtPlatform(String station, String platform);

  /// No description provided for @boardAt.
  ///
  /// In en, this message translates to:
  /// **'Board at {station}'**
  String boardAt(String station);

  /// No description provided for @noIntermediateStops.
  ///
  /// In en, this message translates to:
  /// **'No intermediate stops info.'**
  String get noIntermediateStops;

  /// No description provided for @getOffAtPlatform.
  ///
  /// In en, this message translates to:
  /// **'Get off at {station} (Pl. {platform})'**
  String getOffAtPlatform(String station, String platform);

  /// No description provided for @getOffAt.
  ///
  /// In en, this message translates to:
  /// **'Get off at {station}'**
  String getOffAt(String station);

  /// No description provided for @station.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get station;

  /// No description provided for @friend.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get friend;

  /// No description provided for @friendSelected.
  ///
  /// In en, this message translates to:
  /// **'Friend Selected'**
  String get friendSelected;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @alternatives.
  ///
  /// In en, this message translates to:
  /// **'Alternatives'**
  String get alternatives;

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorPrefix(String error);

  /// No description provided for @toDirection.
  ///
  /// In en, this message translates to:
  /// **'{line} to {dir}'**
  String toDirection(String line, String dir);

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'PREVIOUS'**
  String get previous;

  /// No description provided for @dep.
  ///
  /// In en, this message translates to:
  /// **'DEP'**
  String get dep;

  /// No description provided for @arr.
  ///
  /// In en, this message translates to:
  /// **'ARR'**
  String get arr;

  /// No description provided for @passenger.
  ///
  /// In en, this message translates to:
  /// **'PASSENGER'**
  String get passenger;

  /// No description provided for @walk.
  ///
  /// In en, this message translates to:
  /// **'WALK'**
  String get walk;

  /// No description provided for @transfer.
  ///
  /// In en, this message translates to:
  /// **'TRANSFER'**
  String get transfer;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get noMessagesYet;

  /// No description provided for @cropTicket.
  ///
  /// In en, this message translates to:
  /// **'Crop Ticket'**
  String get cropTicket;

  /// No description provided for @applyCrop.
  ///
  /// In en, this message translates to:
  /// **'Apply Crop'**
  String get applyCrop;

  /// No description provided for @secureChat.
  ///
  /// In en, this message translates to:
  /// **'Secure Chat: {friendName}'**
  String secureChat(String friendName);

  /// No description provided for @noSecureMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No secure messages yet.'**
  String get noSecureMessagesYet;

  /// No description provided for @useImage.
  ///
  /// In en, this message translates to:
  /// **'Use Image'**
  String get useImage;

  /// No description provided for @saySomething.
  ///
  /// In en, this message translates to:
  /// **'Say something...'**
  String get saySomething;

  /// No description provided for @qrCodeDetected.
  ///
  /// In en, this message translates to:
  /// **'QR Code Detected'**
  String get qrCodeDetected;

  /// No description provided for @confirmTicket.
  ///
  /// In en, this message translates to:
  /// **'Confirm Ticket'**
  String get confirmTicket;

  /// No description provided for @detectedQrUseCrop.
  ///
  /// In en, this message translates to:
  /// **'We detected a QR code. Use this crop?'**
  String get detectedQrUseCrop;

  /// No description provided for @noQrUseImage.
  ///
  /// In en, this message translates to:
  /// **'No QR code detected. Use this image?'**
  String get noQrUseImage;

  /// No description provided for @editCrop.
  ///
  /// In en, this message translates to:
  /// **'Edit Crop'**
  String get editCrop;

  /// No description provided for @cropEdit.
  ///
  /// In en, this message translates to:
  /// **'Crop / Edit'**
  String get cropEdit;

  /// No description provided for @renameTicket.
  ///
  /// In en, this message translates to:
  /// **'Rename Ticket'**
  String get renameTicket;

  /// No description provided for @ticketHistory.
  ///
  /// In en, this message translates to:
  /// **'Ticket History'**
  String get ticketHistory;

  /// No description provided for @noHistoryFound.
  ///
  /// In en, this message translates to:
  /// **'No history found.'**
  String get noHistoryFound;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @enterLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter label'**
  String get enterLabel;

  /// No description provided for @errorLoadingTicket.
  ///
  /// In en, this message translates to:
  /// **'Error loading ticket'**
  String get errorLoadingTicket;

  /// No description provided for @changeTicket.
  ///
  /// In en, this message translates to:
  /// **'Change Ticket'**
  String get changeTicket;

  /// No description provided for @addTicket.
  ///
  /// In en, this message translates to:
  /// **'Add Ticket'**
  String get addTicket;

  /// No description provided for @selectImageFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Select image from gallery'**
  String get selectImageFromGallery;

  /// No description provided for @previousSearches.
  ///
  /// In en, this message translates to:
  /// **'Previous Searches'**
  String get previousSearches;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// No description provided for @confirmClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete your recent search history?'**
  String get confirmClearHistory;

  /// No description provided for @searchHistoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Search history cleared.'**
  String get searchHistoryCleared;

  /// No description provided for @myTicket.
  ///
  /// In en, this message translates to:
  /// **'My Ticket'**
  String get myTicket;

  /// No description provided for @generatingStyledQr.
  ///
  /// In en, this message translates to:
  /// **'Generating styled QR...'**
  String get generatingStyledQr;

  /// No description provided for @styledFromOriginalTicketQrPattern.
  ///
  /// In en, this message translates to:
  /// **'Styled from original ticket QR pattern'**
  String get styledFromOriginalTicketQrPattern;

  /// No description provided for @tapForFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Tap for fullscreen'**
  String get tapForFullscreen;

  /// No description provided for @tapForFullscreenHoldForHistory.
  ///
  /// In en, this message translates to:
  /// **'Tap for fullscreen • Hold for history'**
  String get tapForFullscreenHoldForHistory;

  /// No description provided for @showOriginalTicket.
  ///
  /// In en, this message translates to:
  /// **'Show Original Ticket'**
  String get showOriginalTicket;

  /// No description provided for @showStyledQr.
  ///
  /// In en, this message translates to:
  /// **'Show Styled QR'**
  String get showStyledQr;

  /// No description provided for @savedLocallyCloudUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Saved locally. Cloud upload failed.'**
  String get savedLocallyCloudUploadFailed;

  /// No description provided for @couldNotIsolateQrBounds.
  ///
  /// In en, this message translates to:
  /// **'Could not isolate QR bounds. Styling the full image instead.'**
  String get couldNotIsolateQrBounds;

  /// No description provided for @couldNotRecolorQrCode.
  ///
  /// In en, this message translates to:
  /// **'Could not recolor this QR code image.'**
  String get couldNotRecolorQrCode;

  /// No description provided for @transitBoardingPass.
  ///
  /// In en, this message translates to:
  /// **'TRANSIT BOARDING PASS'**
  String get transitBoardingPass;

  /// No description provided for @endOfLine.
  ///
  /// In en, this message translates to:
  /// **'End of Line'**
  String get endOfLine;

  /// No description provided for @wakeAlarmTitle.
  ///
  /// In en, this message translates to:
  /// **'Trans Wake Alarm'**
  String get wakeAlarmTitle;

  /// No description provided for @wakeAlarmTracking.
  ///
  /// In en, this message translates to:
  /// **'Tracking your journey...'**
  String get wakeAlarmTracking;

  /// No description provided for @alternative.
  ///
  /// In en, this message translates to:
  /// **'Alternative'**
  String get alternative;

  /// No description provided for @routeLabel.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get routeLabel;

  /// No description provided for @destinationLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get destinationLabel;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @startNotFound.
  ///
  /// In en, this message translates to:
  /// **'Start not found'**
  String get startNotFound;

  /// No description provided for @destinationNotFound.
  ///
  /// In en, this message translates to:
  /// **'Destination not found'**
  String get destinationNotFound;

  /// No description provided for @departsAt.
  ///
  /// In en, this message translates to:
  /// **'Departs {time}'**
  String departsAt(String time);

  /// No description provided for @lateByMinutes.
  ///
  /// In en, this message translates to:
  /// **'(+{minutes} late)'**
  String lateByMinutes(String minutes);

  /// No description provided for @switchPlatform.
  ///
  /// In en, this message translates to:
  /// **'Switch from {fromPlatform} to {toPlatform}'**
  String switchPlatform(String fromPlatform, String toPlatform);

  /// No description provided for @waitAt.
  ///
  /// In en, this message translates to:
  /// **'Wait at {place}'**
  String waitAt(String place);

  /// No description provided for @transferTo.
  ///
  /// In en, this message translates to:
  /// **'Transfer to {destination}'**
  String transferTo(String destination);

  /// No description provided for @waitForConnection.
  ///
  /// In en, this message translates to:
  /// **'Wait for connection'**
  String get waitForConnection;

  /// No description provided for @walkTo.
  ///
  /// In en, this message translates to:
  /// **'Walk to {destination}'**
  String walkTo(String destination);

  /// No description provided for @walkToDestination.
  ///
  /// In en, this message translates to:
  /// **'Walk to destination'**
  String get walkToDestination;

  /// No description provided for @walkLabel.
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get walkLabel;

  /// No description provided for @atPlatform.
  ///
  /// In en, this message translates to:
  /// **'at {platform}'**
  String atPlatform(String platform);

  /// No description provided for @toPlatform.
  ///
  /// In en, this message translates to:
  /// **'to {platform}'**
  String toPlatform(String platform);

  /// No description provided for @addFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add Favorite'**
  String get addFavorite;

  /// No description provided for @editFavorite.
  ///
  /// In en, this message translates to:
  /// **'Edit Favorite'**
  String get editFavorite;

  /// No description provided for @favoriteLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Label (e.g. Home, Bestie)'**
  String get favoriteLabelHint;

  /// No description provided for @searchStationName.
  ///
  /// In en, this message translates to:
  /// **'Search Station Name'**
  String get searchStationName;

  /// No description provided for @searchFriendUsername.
  ///
  /// In en, this message translates to:
  /// **'Search Friend Username'**
  String get searchFriendUsername;

  /// No description provided for @alarmOn.
  ///
  /// In en, this message translates to:
  /// **'Alarm ON'**
  String get alarmOn;

  /// No description provided for @wakeMe.
  ///
  /// In en, this message translates to:
  /// **'Wake Me'**
  String get wakeMe;

  /// No description provided for @altShort.
  ///
  /// In en, this message translates to:
  /// **'Alt'**
  String get altShort;

  /// No description provided for @blockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Blocked Users'**
  String get blockedUsers;

  /// No description provided for @noBlockedUsers.
  ///
  /// In en, this message translates to:
  /// **'No blocked users'**
  String get noBlockedUsers;

  /// No description provided for @unblockedUser.
  ///
  /// In en, this message translates to:
  /// **'Unblocked {username}'**
  String unblockedUser(String username);

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'This action is irreversible. All your data will be permanently deleted.'**
  String get deleteAccountWarning;

  /// No description provided for @enterPasswordToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password to confirm:'**
  String get enterPasswordToConfirm;

  /// No description provided for @deleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete Forever'**
  String get deleteForever;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Trans'**
  String get appName;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @ghostMode.
  ///
  /// In en, this message translates to:
  /// **'Ghost Mode'**
  String get ghostMode;

  /// No description provided for @hideLocation.
  ///
  /// In en, this message translates to:
  /// **'Hide location from everyone'**
  String get hideLocation;

  /// No description provided for @journeySignal.
  ///
  /// In en, this message translates to:
  /// **'Privacy Level'**
  String get journeySignal;

  /// No description provided for @signalLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String signalLevel(int level);

  /// No description provided for @signalSharingWith.
  ///
  /// In en, this message translates to:
  /// **'Privacy Level for {username}'**
  String signalSharingWith(String username);

  /// No description provided for @signalOverrideExplanation.
  ///
  /// In en, this message translates to:
  /// **'This overrides your global level only for this friend.'**
  String get signalOverrideExplanation;

  /// No description provided for @useGlobalSignal.
  ///
  /// In en, this message translates to:
  /// **'Use global level'**
  String get useGlobalSignal;

  /// No description provided for @friendLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get friendLocation;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @syncedWithSystem.
  ///
  /// In en, this message translates to:
  /// **'Synced with System'**
  String get syncedWithSystem;

  /// No description provided for @systemSyncActive.
  ///
  /// In en, this message translates to:
  /// **'System Sync Active. Long press to disable.'**
  String get systemSyncActive;

  /// No description provided for @systemSyncEnabled.
  ///
  /// In en, this message translates to:
  /// **'System Sync Enabled'**
  String get systemSyncEnabled;

  /// No description provided for @manualModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Manual Mode Enabled'**
  String get manualModeEnabled;

  /// No description provided for @deutschlandTicketMode.
  ///
  /// In en, this message translates to:
  /// **'Deutschlandticket Mode'**
  String get deutschlandTicketMode;

  /// No description provided for @onlyLocalTransport.
  ///
  /// In en, this message translates to:
  /// **'Only local/regional transport'**
  String get onlyLocalTransport;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @showTrainNumbers.
  ///
  /// In en, this message translates to:
  /// **'Show Train Numbers'**
  String get showTrainNumbers;

  /// No description provided for @displayTripIds.
  ///
  /// In en, this message translates to:
  /// **'Display trip IDs (e.g. RE1 (12345))'**
  String get displayTripIds;

  /// No description provided for @notificationsAndHaptics.
  ///
  /// In en, this message translates to:
  /// **'Notifications & Haptics'**
  String get notificationsAndHaptics;

  /// No description provided for @alarmTrigger.
  ///
  /// In en, this message translates to:
  /// **'Alarm Trigger'**
  String get alarmTrigger;

  /// No description provided for @alertAtDestination.
  ///
  /// In en, this message translates to:
  /// **'Alert at destination'**
  String get alertAtDestination;

  /// No description provided for @alertStopsBefore.
  ///
  /// In en, this message translates to:
  /// **'Alert {count} stops before'**
  String alertStopsBefore(String count);

  /// No description provided for @atDest.
  ///
  /// In en, this message translates to:
  /// **'At Dest'**
  String get atDest;

  /// No description provided for @oneStop.
  ///
  /// In en, this message translates to:
  /// **'1 Stop'**
  String get oneStop;

  /// No description provided for @twoStops.
  ///
  /// In en, this message translates to:
  /// **'2 Stops'**
  String get twoStops;

  /// No description provided for @threeStops.
  ///
  /// In en, this message translates to:
  /// **'3 Stops'**
  String get threeStops;

  /// No description provided for @triggerThreshold.
  ///
  /// In en, this message translates to:
  /// **'Trigger Threshold'**
  String get triggerThreshold;

  /// No description provided for @notifyAtThreshold.
  ///
  /// In en, this message translates to:
  /// **'Notify at {threshold} {remaining}'**
  String notifyAtThreshold(String threshold, String remaining);

  /// No description provided for @alarmSound.
  ///
  /// In en, this message translates to:
  /// **'Alarm Sound'**
  String get alarmSound;

  /// No description provided for @previewSound.
  ///
  /// In en, this message translates to:
  /// **'Preview sound'**
  String get previewSound;

  /// No description provided for @wakeAlarmPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Wake alarm preview'**
  String get wakeAlarmPreviewTitle;

  /// No description provided for @wakeAlarmPreviewBody.
  ///
  /// In en, this message translates to:
  /// **'This is how your wake alarm will sound.'**
  String get wakeAlarmPreviewBody;

  /// No description provided for @alarmPattern.
  ///
  /// In en, this message translates to:
  /// **'Alarm Pattern'**
  String get alarmPattern;

  /// No description provided for @ofLegCovered.
  ///
  /// In en, this message translates to:
  /// **'of leg covered'**
  String get ofLegCovered;

  /// No description provided for @fromTarget.
  ///
  /// In en, this message translates to:
  /// **'from target'**
  String get fromTarget;

  /// No description provided for @fivePercentRemaining.
  ///
  /// In en, this message translates to:
  /// **'5% Remaining'**
  String get fivePercentRemaining;

  /// No description provided for @tenPercentRemaining.
  ///
  /// In en, this message translates to:
  /// **'10% Remaining'**
  String get tenPercentRemaining;

  /// No description provided for @fixed500m.
  ///
  /// In en, this message translates to:
  /// **'Fixed 500m'**
  String get fixed500m;

  /// No description provided for @vibrationIntensity.
  ///
  /// In en, this message translates to:
  /// **'Vibration Intensity'**
  String get vibrationIntensity;

  /// No description provided for @alwaysWakeMe.
  ///
  /// In en, this message translates to:
  /// **'Always Wake Me'**
  String get alwaysWakeMe;

  /// No description provided for @turnOnAlarmDefault.
  ///
  /// In en, this message translates to:
  /// **'Turn on alarm for every journey by default'**
  String get turnOnAlarmDefault;

  /// No description provided for @dataAndPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Data & Privacy'**
  String get dataAndPrivacy;

  /// No description provided for @clearSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear Search History'**
  String get clearSearchHistory;

  /// No description provided for @dataSourceAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Data Source (Advanced)'**
  String get dataSourceAdvanced;

  /// No description provided for @transportApi.
  ///
  /// In en, this message translates to:
  /// **'Transport API'**
  String get transportApi;

  /// No description provided for @selectedApiMode.
  ///
  /// In en, this message translates to:
  /// **'Selected: {mode}'**
  String selectedApiMode(String mode);

  /// No description provided for @autoRecommended.
  ///
  /// In en, this message translates to:
  /// **'Auto (Recommended)'**
  String get autoRecommended;

  /// No description provided for @transitousOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Transitous (Open Source)'**
  String get transitousOpenSource;

  /// No description provided for @deutscheBahnLegacy.
  ///
  /// In en, this message translates to:
  /// **'Deutsche Bahn (Legacy)'**
  String get deutscheBahnLegacy;

  /// No description provided for @autoModeShort.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get autoModeShort;

  /// No description provided for @dbV6.
  ///
  /// In en, this message translates to:
  /// **'DB (v6)'**
  String get dbV6;

  /// No description provided for @profileSettings.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileSettings;

  /// No description provided for @noUsername.
  ///
  /// In en, this message translates to:
  /// **'No Username'**
  String get noUsername;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @emailSettings.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailSettings;

  /// No description provided for @newPasswordOpt.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPasswordOpt;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated! Check email for confirmation if changed.'**
  String get profileUpdated;

  /// No description provided for @incorrectPasswordOrRpcMissing.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password.'**
  String get incorrectPasswordOrRpcMissing;

  /// No description provided for @changeUsername.
  ///
  /// In en, this message translates to:
  /// **'Change Username'**
  String get changeUsername;

  /// No description provided for @changeEmail.
  ///
  /// In en, this message translates to:
  /// **'Change Email'**
  String get changeEmail;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @emailChangeHint.
  ///
  /// In en, this message translates to:
  /// **'Changing your email will send a confirmation link before the address updates.'**
  String get emailChangeHint;

  /// No description provided for @passwordChangeHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password for your account.'**
  String get passwordChangeHint;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get passwordsDoNotMatch;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get enterValidEmail;

  /// No description provided for @fillRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Fill in the required fields.'**
  String get fillRequiredFields;

  /// No description provided for @usernameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Username updated.'**
  String get usernameUpdated;

  /// No description provided for @emailUpdateSent.
  ///
  /// In en, this message translates to:
  /// **'Check your email to confirm the address change.'**
  String get emailUpdateSent;

  /// No description provided for @passwordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password updated.'**
  String get passwordUpdated;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOut;

  /// No description provided for @loginSignUp.
  ///
  /// In en, this message translates to:
  /// **'Login / Sign Up'**
  String get loginSignUp;

  /// No description provided for @usernameSignUp.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameSignUp;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @enterEmailReset.
  ///
  /// In en, this message translates to:
  /// **'Enter your email to receive a password reset link.'**
  String get enterEmailReset;

  /// No description provided for @passwordResetEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset email sent (if account exists).'**
  String get passwordResetEmailSent;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @german.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// No description provided for @stopDeparturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Departures at {stopName}'**
  String stopDeparturesTitle(String stopName);

  /// No description provided for @stopDeparturesDate.
  ///
  /// In en, this message translates to:
  /// **'for {date}'**
  String stopDeparturesDate(String date);

  /// No description provided for @stopPlatformFilter.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get stopPlatformFilter;

  /// No description provided for @stopPlatformAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get stopPlatformAll;

  /// No description provided for @stopServiceDayFilter.
  ///
  /// In en, this message translates to:
  /// **'Service Day'**
  String get stopServiceDayFilter;

  /// No description provided for @stopServiceDayWeekday.
  ///
  /// In en, this message translates to:
  /// **'Weekday'**
  String get stopServiceDayWeekday;

  /// No description provided for @stopServiceDayWeekendHoliday.
  ///
  /// In en, this message translates to:
  /// **'Weekend/Holiday'**
  String get stopServiceDayWeekendHoliday;

  /// No description provided for @noDeparturesFound.
  ///
  /// In en, this message translates to:
  /// **'No departures found for this stop.'**
  String get noDeparturesFound;

  /// No description provided for @noDeparturesForPlatform.
  ///
  /// In en, this message translates to:
  /// **'No departures found for this platform.'**
  String get noDeparturesForPlatform;

  /// No description provided for @loadingDepartures.
  ///
  /// In en, this message translates to:
  /// **'Loading departures...'**
  String get loadingDepartures;

  /// No description provided for @stopDeparturesJumpToTop.
  ///
  /// In en, this message translates to:
  /// **'Go to top'**
  String get stopDeparturesJumpToTop;

  /// No description provided for @stopDeparturesJumpToBottom.
  ///
  /// In en, this message translates to:
  /// **'Go to bottom'**
  String get stopDeparturesJumpToBottom;

  /// No description provided for @longPressForDepartures.
  ///
  /// In en, this message translates to:
  /// **'Long-press any stop to see all departures for that day.'**
  String get longPressForDepartures;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
