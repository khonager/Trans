// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Trans';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get resetPasswordMessage =>
      'You have securely logged in via the password reset link. Please set a new password now.';

  @override
  String get resetPasswordSnackbar =>
      'Tap the \'Edit\' icon in your profile to set a new password.';

  @override
  String get ok => 'OK';

  @override
  String get quitAppTitle => 'Quit App?';

  @override
  String get quitAppMessage => 'Do you want to exit the application?';

  @override
  String get no => 'No';

  @override
  String get yes => 'Yes';

  @override
  String get routes => 'Routes';

  @override
  String get friends => 'Friends';

  @override
  String get settings => 'Settings';

  @override
  String get changelogTitle => 'Changelog';

  @override
  String failedToLoadReleases(String statusCode) {
    return 'Failed to load releases: $statusCode';
  }

  @override
  String errorLoadingReleases(String error) {
    return 'Error loading releases: $error';
  }

  @override
  String get retry => 'Retry';

  @override
  String get unknownVersion => 'Unknown Version';

  @override
  String get noDescription => 'No description.';

  @override
  String currentVersionLabel(String tagName) {
    return '$tagName (Current)';
  }

  @override
  String get addNewFriend => 'Add New Friend';

  @override
  String get searchByUsername => 'Search by username...';

  @override
  String requestSentTo(String username) {
    return 'Request sent to @$username';
  }

  @override
  String get friendsTitle => 'Friends';

  @override
  String get activeNow => 'Active Now';

  @override
  String get requests => 'Requests';

  @override
  String get offline => 'Offline';

  @override
  String get noFriendsYet => 'No friends yet.';

  @override
  String get sentFriendRequest => 'Sent a friend request';

  @override
  String get friendRequestAccepted => 'Friend request accepted!';

  @override
  String get friendRequestDenied => 'Friend request denied.';

  @override
  String get inactive => 'Inactive';

  @override
  String get activeRecently => 'Active recently';

  @override
  String onLine(String line) {
    return 'On $line';
  }

  @override
  String lastOnLine(String line) {
    return 'Last on $line';
  }

  @override
  String get activeRecentlyGhost => 'Active recently (Ghost)';

  @override
  String get unknown => 'Unknown';

  @override
  String get chat => 'Chat';

  @override
  String get remove => 'Remove';

  @override
  String removeFriendTitle(String username) {
    return 'Remove $username?';
  }

  @override
  String get removeFriendMessage =>
      'They will be removed from your friends list.';

  @override
  String get cancel => 'Cancel';

  @override
  String get block => 'Block';

  @override
  String removedFriend(String username) {
    return 'Removed $username';
  }

  @override
  String blockedFriend(String username) {
    return 'Blocked $username';
  }

  @override
  String errorString(String error) {
    return 'Error: $error';
  }

  @override
  String routesFound(String count) {
    return '$count Routes Found';
  }

  @override
  String get earliestDep => 'Earliest Dep.';

  @override
  String get earliestArr => 'Earliest Arr.';

  @override
  String get fastest => 'Fastest';

  @override
  String get leastTransfers => 'Least Transfers';

  @override
  String get leastWait => 'Least Wait';

  @override
  String get leastWalking => 'Least Walking';

  @override
  String get loadEarlier => 'Load Earlier';

  @override
  String get loadLater => 'Load Later';

  @override
  String get routeTicketCopied => 'Route ticket copied to clipboard!';

  @override
  String failedToCopy(String error) {
    return 'Failed to copy: $error';
  }

  @override
  String get cancelled => 'CANCELLED';

  @override
  String transfersCount(String count) {
    return '$count transfers';
  }

  @override
  String get locationPermissionDenied =>
      'Location permission denied. Alarm cannot work.';

  @override
  String get locationPermissionPermanentlyDenied =>
      'Location permission permanently denied.';

  @override
  String get missingDestCoords =>
      'Cannot start alarm: Missing destination coordinates.';

  @override
  String wakeUpApproaching(String stop) {
    return 'Wake Up! Approaching $stop!';
  }

  @override
  String get serviceBusyTryAgain =>
      'Service temporarily busy. Try again or type more characters.';

  @override
  String get serviceBusyPleaseTryAgain =>
      'Service temporarily busy. Please try again.';

  @override
  String get locationNotAvailable => 'Location not available.';

  @override
  String get noRoutesFound => 'No routes found.';

  @override
  String get noRoutesFoundBusy =>
      'No routes found. The service may be temporarily busy - please try again.';

  @override
  String get requestTimedOut => 'Request timed out. Please try again.';

  @override
  String get serviceBusyMoment =>
      'Service temporarily busy. Please try again in a moment.';

  @override
  String get weakGps => '⚠️ Weak GPS';

  @override
  String get planJourney => 'Plan Journey';

  @override
  String get tripTime => 'Trip Time';

  @override
  String get now => 'Now';

  @override
  String get currentLocation => 'Current Location';

  @override
  String get fromStationOrAddress => 'Start station or address...';

  @override
  String get toStationOrAddress => 'Destination station or address...';

  @override
  String get stationOrAddress => 'Station or Address...';

  @override
  String get fromLabel => 'From';

  @override
  String get toLabel => 'To';

  @override
  String get arriveBy => 'Arrive by';

  @override
  String get departAt => 'Depart at';

  @override
  String get refreshLocation => 'Refresh location';

  @override
  String get findRoutes => 'Find Routes';

  @override
  String get favorites => 'Favorites';

  @override
  String get add => 'Add';

  @override
  String get frequentJourneys => 'Frequent Journeys';

  @override
  String fromStation(String station) {
    return 'From $station';
  }

  @override
  String couldNotLoadMoreRoutes(String error) {
    return 'Could not load more routes: $error';
  }

  @override
  String couldNotRefreshRoutes(String error) {
    return 'Could not refresh routes: $error';
  }

  @override
  String refreshFailed(String error) {
    return 'Refresh failed: $error';
  }

  @override
  String get cancelledL10n => ' CANCELLED';

  @override
  String boardAtPlatform(String station, String platform) {
    return 'Board at $station (Pl. $platform)';
  }

  @override
  String boardAt(String station) {
    return 'Board at $station';
  }

  @override
  String get noIntermediateStops => 'No intermediate stops info.';

  @override
  String getOffAtPlatform(String station, String platform) {
    return 'Get off at $station (Pl. $platform)';
  }

  @override
  String getOffAt(String station) {
    return 'Get off at $station';
  }

  @override
  String get station => 'Station';

  @override
  String get friend => 'Friend';

  @override
  String get friendSelected => 'Friend Selected';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get alternatives => 'Alternatives';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String toDirection(String line, String dir) {
    return '$line to $dir';
  }

  @override
  String get previous => 'PREVIOUS';

  @override
  String get dep => 'DEP';

  @override
  String get arr => 'ARR';

  @override
  String get passenger => 'PASSENGER';

  @override
  String get walk => 'WALK';

  @override
  String get transfer => 'TRANSFER';

  @override
  String get noMessagesYet => 'No messages yet.';

  @override
  String get cropTicket => 'Crop Ticket';

  @override
  String get applyCrop => 'Apply Crop';

  @override
  String secureChat(String friendName) {
    return 'Secure Chat: $friendName';
  }

  @override
  String get noSecureMessagesYet => 'No secure messages yet.';

  @override
  String get useImage => 'Use Image';

  @override
  String get saySomething => 'Say something...';

  @override
  String get qrCodeDetected => 'QR Code Detected';

  @override
  String get confirmTicket => 'Confirm Ticket';

  @override
  String get detectedQrUseCrop => 'We detected a QR code. Use this crop?';

  @override
  String get noQrUseImage => 'No QR code detected. Use this image?';

  @override
  String get editCrop => 'Edit Crop';

  @override
  String get cropEdit => 'Crop / Edit';

  @override
  String get renameTicket => 'Rename Ticket';

  @override
  String get ticketHistory => 'Ticket History';

  @override
  String get noHistoryFound => 'No history found.';

  @override
  String get rename => 'Rename';

  @override
  String get enterLabel => 'Enter label';

  @override
  String get errorLoadingTicket => 'Error loading ticket';

  @override
  String get changeTicket => 'Change Ticket';

  @override
  String get addTicket => 'Add Ticket';

  @override
  String get selectImageFromGallery => 'Select image from gallery';

  @override
  String get previousSearches => 'Previous Searches';

  @override
  String get clearHistory => 'Clear History';

  @override
  String get confirmClearHistory =>
      'Are you sure you want to delete your recent search history?';

  @override
  String get searchHistoryCleared => 'Search history cleared.';

  @override
  String get myTicket => 'My Ticket';

  @override
  String get generatingStyledQr => 'Generating styled QR...';

  @override
  String get styledFromOriginalTicketQrPattern =>
      'Styled from original ticket QR pattern';

  @override
  String get tapForFullscreen => 'Tap for fullscreen';

  @override
  String get tapForFullscreenHoldForHistory =>
      'Tap for fullscreen • Hold for history';

  @override
  String get showOriginalTicket => 'Show Original Ticket';

  @override
  String get showStyledQr => 'Show Styled QR';

  @override
  String get savedLocallyCloudUploadFailed =>
      'Saved locally. Cloud upload failed.';

  @override
  String get couldNotIsolateQrBounds =>
      'Could not isolate QR bounds. Styling the full image instead.';

  @override
  String get couldNotRecolorQrCode => 'Could not recolor this QR code image.';

  @override
  String get transitBoardingPass => 'TRANSIT BOARDING PASS';

  @override
  String get endOfLine => 'End of Line';

  @override
  String get wakeAlarmTitle => 'Trans Wake Alarm';

  @override
  String get wakeAlarmTracking => 'Tracking your journey...';

  @override
  String get alternative => 'Alternative';

  @override
  String get routeLabel => 'Route';

  @override
  String get destinationLabel => 'Destination';

  @override
  String get details => 'Details';

  @override
  String get startNotFound => 'Start not found';

  @override
  String get destinationNotFound => 'Destination not found';

  @override
  String departsAt(String time) {
    return 'Departs $time';
  }

  @override
  String lateByMinutes(String minutes) {
    return '(+$minutes late)';
  }

  @override
  String switchPlatform(String fromPlatform, String toPlatform) {
    return 'Switch from $fromPlatform to $toPlatform';
  }

  @override
  String waitAt(String place) {
    return 'Wait at $place';
  }

  @override
  String transferTo(String destination) {
    return 'Transfer to $destination';
  }

  @override
  String get waitForConnection => 'Wait for connection';

  @override
  String walkTo(String destination) {
    return 'Walk to $destination';
  }

  @override
  String get walkToDestination => 'Walk to destination';

  @override
  String get walkLabel => 'Walk';

  @override
  String atPlatform(String platform) {
    return 'at $platform';
  }

  @override
  String toPlatform(String platform) {
    return 'to $platform';
  }

  @override
  String get addFavorite => 'Add Favorite';

  @override
  String get editFavorite => 'Edit Favorite';

  @override
  String get favoriteLabelHint => 'Label (e.g. Home, Bestie)';

  @override
  String get searchStationName => 'Search Station Name';

  @override
  String get searchFriendUsername => 'Search Friend Username';

  @override
  String get alarmOn => 'Alarm ON';

  @override
  String get wakeMe => 'Wake Me';

  @override
  String get altShort => 'Alt';

  @override
  String get blockedUsers => 'Blocked Users';

  @override
  String get noBlockedUsers => 'No blocked users';

  @override
  String unblockedUser(String username) {
    return 'Unblocked $username';
  }

  @override
  String get unblock => 'Unblock';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get deleteAccountWarning =>
      'This action is irreversible. All your data will be permanently deleted.';

  @override
  String get enterPasswordToConfirm => 'Please enter your password to confirm:';

  @override
  String get deleteForever => 'Delete Forever';

  @override
  String get appName => 'Trans';

  @override
  String get privacy => 'Privacy';

  @override
  String get ghostMode => 'Ghost Mode';

  @override
  String get hideLocation => 'Hide location from everyone';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get syncedWithSystem => 'Synced with System';

  @override
  String get systemSyncActive => 'System Sync Active. Long press to disable.';

  @override
  String get systemSyncEnabled => 'System Sync Enabled';

  @override
  String get manualModeEnabled => 'Manual Mode Enabled';

  @override
  String get deutschlandTicketMode => 'Deutschlandticket Mode';

  @override
  String get onlyLocalTransport => 'Only local/regional transport';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeColor => 'Theme Color';

  @override
  String get showTrainNumbers => 'Show Train Numbers';

  @override
  String get displayTripIds => 'Display trip IDs (e.g. RE1 (12345))';

  @override
  String get notificationsAndHaptics => 'Notifications & Haptics';

  @override
  String get alarmTrigger => 'Alarm Trigger';

  @override
  String get alertAtDestination => 'Alert at destination';

  @override
  String alertStopsBefore(String count) {
    return 'Alert $count stops before';
  }

  @override
  String get atDest => 'At Dest';

  @override
  String get oneStop => '1 Stop';

  @override
  String get twoStops => '2 Stops';

  @override
  String get threeStops => '3 Stops';

  @override
  String get triggerThreshold => 'Trigger Threshold';

  @override
  String notifyAtThreshold(String threshold, String remaining) {
    return 'Notify at $threshold $remaining';
  }

  @override
  String get alarmPattern => 'Alarm Pattern';

  @override
  String get ofLegCovered => 'of leg covered';

  @override
  String get fromTarget => 'from target';

  @override
  String get fivePercentRemaining => '5% Remaining';

  @override
  String get tenPercentRemaining => '10% Remaining';

  @override
  String get fixed500m => 'Fixed 500m';

  @override
  String get vibrationIntensity => 'Vibration Intensity';

  @override
  String get alwaysWakeMe => 'Always Wake Me';

  @override
  String get turnOnAlarmDefault => 'Turn on alarm for every journey by default';

  @override
  String get dataAndPrivacy => 'Data & Privacy';

  @override
  String get clearSearchHistory => 'Clear Search History';

  @override
  String get dataSourceAdvanced => 'Data Source (Advanced)';

  @override
  String get transportApi => 'Transport API';

  @override
  String selectedApiMode(String mode) {
    return 'Selected: $mode';
  }

  @override
  String get autoRecommended => 'Auto (Recommended)';

  @override
  String get transitousOpenSource => 'Transitous (Open Source)';

  @override
  String get deutscheBahnLegacy => 'Deutsche Bahn (Legacy)';

  @override
  String get autoModeShort => 'Auto';

  @override
  String get dbV6 => 'DB (v6)';

  @override
  String get profileSettings => 'Profile';

  @override
  String get noUsername => 'No Username';

  @override
  String get username => 'Username';

  @override
  String get emailSettings => 'Email';

  @override
  String get newPasswordOpt => 'New Password';

  @override
  String get profileUpdated =>
      'Profile updated! Check email for confirmation if changed.';

  @override
  String get incorrectPasswordOrRpcMissing => 'Incorrect password.';

  @override
  String get changeUsername => 'Change Username';

  @override
  String get changeEmail => 'Change Email';

  @override
  String get changePassword => 'Change Password';

  @override
  String get emailChangeHint =>
      'Changing your email will send a confirmation link before the address updates.';

  @override
  String get passwordChangeHint => 'Choose a new password for your account.';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match.';

  @override
  String get enterValidEmail => 'Enter a valid email address.';

  @override
  String get fillRequiredFields => 'Fill in the required fields.';

  @override
  String get usernameUpdated => 'Username updated.';

  @override
  String get emailUpdateSent =>
      'Check your email to confirm the address change.';

  @override
  String get passwordUpdated => 'Password updated.';

  @override
  String get update => 'Update';

  @override
  String get logOut => 'Log Out';

  @override
  String get loginSignUp => 'Login / Sign Up';

  @override
  String get usernameSignUp => 'Username';

  @override
  String get password => 'Password';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get login => 'Login';

  @override
  String get signUp => 'Sign Up';

  @override
  String get enterEmailReset =>
      'Enter your email to receive a password reset link.';

  @override
  String get passwordResetEmailSent =>
      'Password reset email sent (if account exists).';

  @override
  String get send => 'Send';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get german => 'German';

  @override
  String stopDeparturesTitle(String stopName) => 'Departures at $stopName';

  @override
  String stopDeparturesDate(String date) => 'for $date';

  @override
  String get noDeparturesFound => 'No departures found for this stop.';

  @override
  String get loadingDepartures => 'Loading departures...';

  @override
  String get longPressForDepartures =>
      'Long-press any stop to see all departures for that day.';
}
