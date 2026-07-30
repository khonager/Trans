// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Trans';

  @override
  String get resetPassword => 'Passwort zurücksetzen';

  @override
  String get resetPasswordMessage =>
      'Sie haben sich sicher über den Link zum Zurücksetzen des Passworts angemeldet. Bitte legen Sie nun ein neues Passwort fest.';

  @override
  String get resetPasswordSnackbar =>
      'Tippen Sie auf das \'Bearbeiten\'-Symbol in Ihrem Profil, um ein neues Passwort festzulegen.';

  @override
  String get ok => 'OK';

  @override
  String get quitAppTitle => 'App beenden?';

  @override
  String get quitAppMessage => 'Möchten Sie die Anwendung wirklich beenden?';

  @override
  String get no => 'Nein';

  @override
  String get yes => 'Ja';

  @override
  String get routes => 'Routen';

  @override
  String get friends => 'Freunde';

  @override
  String get settings => 'Einstellungen';

  @override
  String get changelogTitle => 'Änderungsprotokoll';

  @override
  String failedToLoadReleases(String statusCode) {
    return 'Fehler beim Laden von Versionen: $statusCode';
  }

  @override
  String errorLoadingReleases(String error) {
    return 'Fehler beim Laden von Versionen: $error';
  }

  @override
  String get retry => 'Wiederholen';

  @override
  String get unknownVersion => 'Unbekannte Version';

  @override
  String get noDescription => 'Keine Beschreibung.';

  @override
  String currentVersionLabel(String tagName) {
    return '$tagName (Aktuell)';
  }

  @override
  String get addNewFriend => 'Neuen Freund hinzufügen';

  @override
  String get searchByUsername => 'Nach Benutzernamen suchen...';

  @override
  String requestSentTo(String username) {
    return 'Anfrage gesendet an @$username';
  }

  @override
  String get friendsTitle => 'Freunde';

  @override
  String get activeNow => 'Jetzt aktiv';

  @override
  String get requests => 'Anfragen';

  @override
  String get offline => 'Offline';

  @override
  String get noFriendsYet => 'Noch keine Freunde.';

  @override
  String get sentFriendRequest => 'Freundschaftsanfrage gesendet';

  @override
  String get friendRequestAccepted => 'Freundschaftsanfrage akzeptiert!';

  @override
  String get friendRequestDenied => 'Freundschaftsanfrage abgelehnt.';

  @override
  String get inactive => 'Inaktiv';

  @override
  String get activeRecently => 'Kürzlich aktiv';

  @override
  String onLine(String line) {
    return 'In $line';
  }

  @override
  String lastOnLine(String line) {
    return 'Zuletzt in $line';
  }

  @override
  String get activeRecentlyGhost => 'Kürzlich aktiv (Geist-Modus)';

  @override
  String get unknown => 'Unbekannt';

  @override
  String get chat => 'Chat';

  @override
  String get remove => 'Entfernen';

  @override
  String removeFriendTitle(String username) {
    return '$username entfernen?';
  }

  @override
  String get removeFriendMessage =>
      'Sie werden aus Ihrer Freundesliste entfernt.';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get block => 'Blockieren';

  @override
  String removedFriend(String username) {
    return '$username entfernt';
  }

  @override
  String blockedFriend(String username) {
    return '$username blockiert';
  }

  @override
  String errorString(String error) {
    return 'Fehler: $error';
  }

  @override
  String routesFound(String count) {
    return '$count Routen gefunden';
  }

  @override
  String get earliestDep => 'Früheste Abf.';

  @override
  String get earliestArr => 'Früheste Ank.';

  @override
  String get fastest => 'Schnellste';

  @override
  String get leastTransfers => 'Wenigste Umst.';

  @override
  String get leastWait => 'Wenigste Wartezeit';

  @override
  String get leastWalking => 'Wenigster Fußweg';

  @override
  String get loadEarlier => 'Frühere laden';

  @override
  String get loadLater => 'Spätere laden';

  @override
  String get routeTicketCopied => 'Routenticket in die Zwischenablage kopiert!';

  @override
  String failedToCopy(String error) {
    return 'Kopieren fehlgeschlagen: $error';
  }

  @override
  String get cancelled => 'FÄLLT AUS';

  @override
  String transfersCount(String count) {
    return '$count Umstiege';
  }

  @override
  String get locationPermissionDenied =>
      'Standortberechtigung verweigert. Alarm funktioniert nicht.';

  @override
  String get locationPermissionPermanentlyDenied =>
      'Standortberechtigung dauerhaft verweigert.';

  @override
  String get missingDestCoords =>
      'Alarm kann nicht gestartet werden: Zielkoordinaten fehlen.';

  @override
  String wakeUpApproaching(String stop) {
    return 'Aufwachen! Sie nähern sich $stop!';
  }

  @override
  String get serviceBusyTryAgain =>
      'Dienst vorübergehend ausgelastet. Versuchen Sie es erneut oder geben Sie mehr Zeichen ein.';

  @override
  String get serviceBusyPleaseTryAgain =>
      'Dienst vorübergehend ausgelastet. Bitte versuchen Sie es erneut.';

  @override
  String get locationNotAvailable => 'Standort nicht verfügbar.';

  @override
  String get noRoutesFound => 'Keine Routen gefunden.';

  @override
  String get noRoutesFoundBusy =>
      'Keine Routen gefunden. Der Dienst ist möglicherweise ausgelastet.';

  @override
  String get requestTimedOut =>
      'Zeitüberschreitung der Anfrage. Bitte versuchen Sie es erneut.';

  @override
  String get serviceBusyMoment =>
      'Dienst ausgelastet. Bitte versuchen Sie es gleich noch einmal.';

  @override
  String get weakGps => '⚠️ Schwaches GPS';

  @override
  String get planJourney => 'Reise planen';

  @override
  String get tripTime => 'Reisezeit';

  @override
  String get now => 'Jetzt';

  @override
  String get currentLocation => 'Aktueller Standort';

  @override
  String get fromStationOrAddress => 'Startstation oder Adresse...';

  @override
  String get toStationOrAddress => 'Zielstation oder Adresse...';

  @override
  String get stationOrAddress => 'Station oder Adresse...';

  @override
  String get fromLabel => 'Von';

  @override
  String get toLabel => 'Nach';

  @override
  String get arriveBy => 'Ankunft bis';

  @override
  String get departAt => 'Abfahrt um';

  @override
  String get refreshLocation => 'Standort aktualisieren';

  @override
  String get findRoutes => 'Routen finden';

  @override
  String get favorites => 'Favoriten';

  @override
  String get add => 'Hinzufügen';

  @override
  String get frequentJourneys => 'Häufige Reisen';

  @override
  String fromStation(String station) {
    return 'Von $station';
  }

  @override
  String couldNotLoadMoreRoutes(String error) {
    return 'Weitere Routen konnten nicht geladen werden: $error';
  }

  @override
  String couldNotRefreshRoutes(String error) {
    return 'Routen konnten nicht aktualisiert werden: $error';
  }

  @override
  String refreshFailed(String error) {
    return 'Aktualisierung fehlgeschlagen: $error';
  }

  @override
  String get cancelledL10n => ' FÄLLT AUS';

  @override
  String boardAtPlatform(String station, String platform) {
    return 'Einsteigen in $station (Gl. $platform)';
  }

  @override
  String boardAt(String station) {
    return 'Einsteigen in $station';
  }

  @override
  String get noIntermediateStops => 'Keine Zwischenhalte-Infos.';

  @override
  String getOffAtPlatform(String station, String platform) {
    return 'Aussteigen in $station (Gl. $platform)';
  }

  @override
  String getOffAt(String station) {
    return 'Aussteigen in $station';
  }

  @override
  String get station => 'Station';

  @override
  String get friend => 'Freund';

  @override
  String get friendSelected => 'Freund ausgewählt';

  @override
  String get delete => 'Löschen';

  @override
  String get save => 'Speichern';

  @override
  String get alternatives => 'Alternativen';

  @override
  String errorPrefix(String error) {
    return 'Fehler: $error';
  }

  @override
  String toDirection(String line, String dir) {
    return '$line nach $dir';
  }

  @override
  String get previous => 'Frühere';

  @override
  String get dep => 'ABF';

  @override
  String get arr => 'ANK';

  @override
  String get passenger => 'FAHRGAST';

  @override
  String get walk => 'GEHEN';

  @override
  String get transfer => 'UMSTIEG';

  @override
  String get noMessagesYet => 'Noch keine Nachrichten.';

  @override
  String get cropTicket => 'Ticket zuschneiden';

  @override
  String get applyCrop => 'Zuschnitt übernehmen';

  @override
  String secureChat(String friendName) {
    return 'Sicherer Chat: $friendName';
  }

  @override
  String get noSecureMessagesYet => 'Keine sicheren Nachrichten bisher.';

  @override
  String get useImage => 'Bild verwenden';

  @override
  String get saySomething => 'Nachricht schreiben...';

  @override
  String get qrCodeDetected => 'QR-Code erkannt';

  @override
  String get confirmTicket => 'Ticket bestätigen';

  @override
  String get detectedQrUseCrop =>
      'Wir haben einen QR-Code erkannt. Diesen Zuschnitt verwenden?';

  @override
  String get noQrUseImage => 'Kein QR-Code erkannt. Dieses Bild verwenden?';

  @override
  String get editCrop => 'Zuschnitt bearbeiten';

  @override
  String get cropEdit => 'Zuschneiden / Bearbeiten';

  @override
  String get renameTicket => 'Ticket umbenennen';

  @override
  String get ticketHistory => 'Ticket-Verlauf';

  @override
  String get noHistoryFound => 'Kein Verlauf gefunden.';

  @override
  String get rename => 'Umbenennen';

  @override
  String get enterLabel => 'Bezeichnung eingeben';

  @override
  String get errorLoadingTicket => 'Fehler beim Laden des Tickets';

  @override
  String get changeTicket => 'Ticket ändern';

  @override
  String get addTicket => 'Ticket hinzufügen';

  @override
  String get selectImageFromGallery => 'Bild aus Galerie wählen';

  @override
  String get previousSearches => 'Vorherige Suchen';

  @override
  String get clearHistory => 'Verlauf löschen';

  @override
  String get confirmClearHistory =>
      'Sind Sie sicher, dass Sie Ihren Suchverlauf löschen möchten?';

  @override
  String get searchHistoryCleared => 'Suchverlauf gelöscht.';

  @override
  String get myTicket => 'Mein Ticket';

  @override
  String get generatingStyledQr => 'Stilisierter QR-Code wird erstellt...';

  @override
  String get styledFromOriginalTicketQrPattern =>
      'Aus dem QR-Muster des Originaltickets erstellt';

  @override
  String get tapForFullscreen => 'Tippen für Vollbild';

  @override
  String get tapForFullscreenHoldForHistory =>
      'Tippen für Vollbild • Halten für Verlauf';

  @override
  String get showOriginalTicket => 'Originalticket anzeigen';

  @override
  String get showStyledQr => 'Stilisierten QR-Code anzeigen';

  @override
  String get savedLocallyCloudUploadFailed =>
      'Lokal gespeichert. Cloud-Upload fehlgeschlagen.';

  @override
  String get couldNotIsolateQrBounds =>
      'QR-Bereich konnte nicht sauber erkannt werden. Stattdessen wird das ganze Bild stilisiert.';

  @override
  String get couldNotRecolorQrCode =>
      'Dieses QR-Code-Bild konnte nicht umgefärbt werden.';

  @override
  String get transitBoardingPass => 'FAHRKARTE';

  @override
  String get endOfLine => 'Endstation';

  @override
  String get wakeAlarmTitle => 'Trans-Weckalarm';

  @override
  String get wakeAlarmTracking => 'Ihre Reise wird verfolgt...';

  @override
  String get alternative => 'Alternative';

  @override
  String get routeLabel => 'Route';

  @override
  String get destinationLabel => 'Ziel';

  @override
  String get details => 'Details';

  @override
  String get startNotFound => 'Start nicht gefunden';

  @override
  String get destinationNotFound => 'Ziel nicht gefunden';

  @override
  String departsAt(String time) {
    return 'Abfahrt $time';
  }

  @override
  String lateByMinutes(String minutes) {
    return '(+$minutes Min. verspätet)';
  }

  @override
  String switchPlatform(String fromPlatform, String toPlatform) {
    return 'Wechsel von $fromPlatform zu $toPlatform';
  }

  @override
  String waitAt(String place) {
    return 'Warten bei $place';
  }

  @override
  String transferTo(String destination) {
    return 'Umsteigen nach $destination';
  }

  @override
  String get waitForConnection => 'Auf Anschluss warten';

  @override
  String walkTo(String destination) {
    return 'Zu $destination laufen';
  }

  @override
  String get walkToDestination => 'Zum Ziel laufen';

  @override
  String get walkLabel => 'Laufen';

  @override
  String atPlatform(String platform) {
    return 'bei $platform';
  }

  @override
  String toPlatform(String platform) {
    return 'zu $platform';
  }

  @override
  String get addFavorite => 'Favorit hinzufügen';

  @override
  String get editFavorite => 'Favorit bearbeiten';

  @override
  String get favoriteLabelHint => 'Bezeichnung (z. B. Zuhause, Bestie)';

  @override
  String get searchStationName => 'Stationsnamen suchen';

  @override
  String get searchFriendUsername => 'Freundes-Benutzernamen suchen';

  @override
  String get alarmOn => 'Alarm an';

  @override
  String get wakeMe => 'Weck mich';

  @override
  String get altShort => 'Alt';

  @override
  String get blockedUsers => 'Blockierte Nutzer';

  @override
  String get noBlockedUsers => 'Keine blockierten Nutzer';

  @override
  String unblockedUser(String username) {
    return '$username entsperrt';
  }

  @override
  String get unblock => 'Entsperren';

  @override
  String get deleteAccount => 'Konto löschen';

  @override
  String get deleteAccountWarning =>
      'Diese Aktion ist unwiderruflich. Alle Ihre Daten werden dauerhaft gelöscht.';

  @override
  String get enterPasswordToConfirm =>
      'Bitte geben Sie Ihr Passwort zur Bestätigung ein:';

  @override
  String get deleteForever => 'Dauerhaft löschen';

  @override
  String get appName => 'Trans';

  @override
  String get privacy => 'Datenschutz';

  @override
  String get ghostMode => 'Geist-Modus';

  @override
  String get hideLocation => 'Standort vor allen verbergen';

  @override
  String get journeySignal => 'Datenschutzstufe';

  @override
  String signalLevel(int level) {
    return 'Stufe $level';
  }

  @override
  String signalSharingWith(String username) {
    return 'Datenschutzstufe für $username';
  }

  @override
  String get signalOverrideExplanation =>
      'Dies überschreibt deine globale Stufe nur für diesen Freund.';

  @override
  String get useGlobalSignal => 'Globale Stufe verwenden';

  @override
  String get friendLocation => 'Standort';

  @override
  String get darkMode => 'Dunkelmodus';

  @override
  String get syncedWithSystem => 'Mit System synchronisiert';

  @override
  String get systemSyncActive =>
      'System-Sync aktiv. Gedrückt halten zum Deaktivieren.';

  @override
  String get systemSyncEnabled => 'System-Sync aktiviert';

  @override
  String get manualModeEnabled => 'Manueller Modus aktiviert';

  @override
  String get deutschlandTicketMode => 'Deutschlandticket-Modus';

  @override
  String get onlyLocalTransport => 'Nur Nahverkehr';

  @override
  String get appearance => 'Erscheinungsbild';

  @override
  String get themeColor => 'Designfarbe';

  @override
  String get showTrainNumbers => 'Zugnummern anzeigen';

  @override
  String get displayTripIds => 'Fahrt-IDs anzeigen (z.B. RE1 (12345))';

  @override
  String get notificationsAndHaptics => 'Benachrichtigungen & Haptik';

  @override
  String get alarmTrigger => 'Alarm-Auslöser';

  @override
  String get alertAtDestination => 'Alarm am Ziel';

  @override
  String alertStopsBefore(String count) {
    return 'Alarm $count Haltestellen vorher';
  }

  @override
  String get atDest => 'Am Ziel';

  @override
  String get oneStop => '1 Halt';

  @override
  String get twoStops => '2 Halte';

  @override
  String get threeStops => '3 Halte';

  @override
  String get triggerThreshold => 'Auslöseschwelle';

  @override
  String notifyAtThreshold(String threshold, String remaining) {
    return 'Benachrichtigung bei $threshold $remaining';
  }

  @override
  String get alarmSound => 'Alarmton';

  @override
  String get previewSound => 'Ton testen';

  @override
  String get wakeAlarmPreviewTitle => 'Weckalarm-Vorschau';

  @override
  String get wakeAlarmPreviewBody => 'So wird dein Weckalarm klingen.';

  @override
  String get alarmPattern => 'Alarm-Muster';

  @override
  String get ofLegCovered => 'der Strecke geschafft';

  @override
  String get fromTarget => 'bis zum Ziel';

  @override
  String get fivePercentRemaining => '5 % verbleibend';

  @override
  String get tenPercentRemaining => '10 % verbleibend';

  @override
  String get fixed500m => 'Feste 500 m';

  @override
  String get vibrationIntensity => 'Vibrationsintensität';

  @override
  String get alwaysWakeMe => 'Immer wecken';

  @override
  String get turnOnAlarmDefault => 'Alarm immer standardmäßig aktivieren';

  @override
  String get dataAndPrivacy => 'Daten & Datenschutz';

  @override
  String get clearSearchHistory => 'Suchverlauf leeren';

  @override
  String get dataSourceAdvanced => 'Datenquelle (Erweitert)';

  @override
  String get transportApi => 'Transport-API';

  @override
  String selectedApiMode(String mode) {
    return 'Ausgewählt: $mode';
  }

  @override
  String get autoRecommended => 'Auto (Empfohlen)';

  @override
  String get transitousOpenSource => 'Transitous (Open Source)';

  @override
  String get deutscheBahnLegacy => 'Deutsche Bahn (Legacy)';

  @override
  String get autoModeShort => 'Auto';

  @override
  String get dbV6 => 'DB (v6)';

  @override
  String get profileSettings => 'Profil';

  @override
  String get noUsername => 'Kein Benutzername';

  @override
  String get username => 'Benutzername';

  @override
  String get emailSettings => 'E-Mail';

  @override
  String get newPasswordOpt => 'Neues Passwort';

  @override
  String get profileUpdated =>
      'Profil aktualisiert! Bitte E-Mail auf Bestätigung prüfen (falls geändert).';

  @override
  String get incorrectPasswordOrRpcMissing => 'Falsches Passwort.';

  @override
  String get changeUsername => 'Benutzernamen ändern';

  @override
  String get changeEmail => 'E-Mail ändern';

  @override
  String get changePassword => 'Passwort ändern';

  @override
  String get emailChangeHint =>
      'Beim Ändern der E-Mail wird zuerst ein Bestätigungslink gesendet.';

  @override
  String get passwordChangeHint =>
      'Wählen Sie ein neues Passwort für Ihr Konto.';

  @override
  String get confirmPassword => 'Passwort bestätigen';

  @override
  String get passwordsDoNotMatch => 'Die Passwörter stimmen nicht überein.';

  @override
  String get enterValidEmail => 'Geben Sie eine gültige E-Mail-Adresse ein.';

  @override
  String get fillRequiredFields =>
      'Bitte füllen Sie die erforderlichen Felder aus.';

  @override
  String get usernameUpdated => 'Benutzername aktualisiert.';

  @override
  String get emailUpdateSent =>
      'Bitte prüfen Sie Ihre E-Mails, um die Adressänderung zu bestätigen.';

  @override
  String get passwordUpdated => 'Passwort aktualisiert.';

  @override
  String get update => 'Aktualisieren';

  @override
  String get logOut => 'Abmelden';

  @override
  String get loginSignUp => 'Anmelden / Registrieren';

  @override
  String get usernameSignUp => 'Benutzername';

  @override
  String get password => 'Passwort';

  @override
  String get forgotPassword => 'Passwort vergessen?';

  @override
  String get login => 'Anmelden';

  @override
  String get signUp => 'Registrieren';

  @override
  String get enterEmailReset =>
      'Geben Sie Ihre E-Mail ein, um einen Zurücksetzen-Link zu erhalten.';

  @override
  String get passwordResetEmailSent =>
      'E-Mail zum Zurücksetzen gesendet (falls Konto existiert).';

  @override
  String get send => 'Senden';

  @override
  String get language => 'Sprache';

  @override
  String get english => 'Englisch';

  @override
  String get german => 'Deutsch';

  @override
  String stopDeparturesTitle(String stopName) {
    return 'Abfahrten an $stopName';
  }

  @override
  String stopDeparturesDate(String date) {
    return 'am $date';
  }

  @override
  String get stopPlatformFilter => 'Steig / Gleis';

  @override
  String get stopPlatformAll => 'Alle';

  @override
  String get stopServiceDayFilter => 'Verkehrstag';

  @override
  String get stopServiceDayWeekday => 'Werktag';

  @override
  String get stopServiceDayWeekendHoliday => 'Wochenende/Feiertag';

  @override
  String get noDeparturesFound =>
      'Keine Abfahrten für diese Haltestelle gefunden.';

  @override
  String get noDeparturesForPlatform =>
      'Keine Abfahrten für diesen Steig gefunden.';

  @override
  String get loadingDepartures => 'Abfahrten werden geladen...';

  @override
  String get stopDeparturesJumpToTop => 'Nach oben';

  @override
  String get stopDeparturesJumpToBottom => 'Nach unten';

  @override
  String get longPressForDepartures =>
      'Haltestelle lang drücken, um alle Abfahrten des Tages zu sehen.';
}
