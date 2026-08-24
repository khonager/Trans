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
      'Du bist sicher über den Link zum Zurücksetzen des Passworts angemeldet. Lege jetzt bitte ein neues Passwort fest.';

  @override
  String get resetPasswordSnackbar =>
      'Tippe in deinem Profil auf das Bearbeiten-Symbol, um ein neues Passwort festzulegen.';

  @override
  String get ok => 'OK';

  @override
  String get quitAppTitle => 'App beenden?';

  @override
  String get quitAppMessage => 'Möchtest du die App wirklich beenden?';

  @override
  String get no => 'Nein';

  @override
  String get yes => 'Ja';

  @override
  String get routes => 'Verbindungen';

  @override
  String get friends => 'Freunde';

  @override
  String get settings => 'Einstellungen';

  @override
  String get changelogTitle => 'Neuerungen';

  @override
  String failedToLoadReleases(String statusCode) {
    return 'Versionen konnten nicht geladen werden: $statusCode';
  }

  @override
  String errorLoadingReleases(String error) {
    return 'Fehler beim Laden der Versionen: $error';
  }

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get unknownVersion => 'Unbekannte Version';

  @override
  String get noDescription => 'Keine Beschreibung.';

  @override
  String currentVersionLabel(String tagName) {
    return '$tagName (aktuell)';
  }

  @override
  String get addNewFriend => 'Freund hinzufügen';

  @override
  String get searchByUsername => 'Nach Benutzernamen suchen...';

  @override
  String requestSentTo(String username) {
    return 'Anfrage an @$username gesendet';
  }

  @override
  String get friendsTitle => 'Freunde';

  @override
  String get activeNow => 'Gerade aktiv';

  @override
  String get requests => 'Anfragen';

  @override
  String get offline => 'Offline';

  @override
  String get noFriendsYet => 'Noch keine Freunde.';

  @override
  String get sentFriendRequest => 'Freundschaftsanfrage gesendet';

  @override
  String get sentRequests => 'Gesendete Anfragen';

  @override
  String get requestPending => 'Wartet auf Antwort';

  @override
  String get cancelRequest => 'Anfrage zurückziehen';

  @override
  String requestCancelledFor(String username) {
    return 'Anfrage an @$username zurückgezogen';
  }

  @override
  String get friendRequestAccepted => 'Freundschaftsanfrage angenommen!';

  @override
  String get friendRequestDenied => 'Freundschaftsanfrage abgelehnt.';

  @override
  String get inactive => 'Inaktiv';

  @override
  String get activeRecently => 'Kürzlich aktiv';

  @override
  String onLine(String line) {
    return 'Unterwegs mit $line';
  }

  @override
  String lastOnLine(String line) {
    return 'Zuletzt mit $line';
  }

  @override
  String get activeRecentlyGhost => 'Kürzlich aktiv (Ghost-Modus)';

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
      'Die Person wird aus deiner Freundesliste entfernt.';

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
    return '$count Verbindungen gefunden';
  }

  @override
  String get earliestDep => 'Früheste Abf.';

  @override
  String get earliestArr => 'Früheste Ank.';

  @override
  String get fastest => 'Schnellste';

  @override
  String get leastTransfers => 'Wenig Umstiege';

  @override
  String get leastWait => 'Kurze Wartezeit';

  @override
  String get leastWalking => 'Kurzer Fußweg';

  @override
  String get loadEarlier => 'Frühere Verbindungen';

  @override
  String get loadLater => 'Spätere Verbindungen';

  @override
  String get routeTicketCopied => 'Ticket in die Zwischenablage kopiert!';

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
      'Standortberechtigung verweigert. Der Alarm funktioniert so nicht.';

  @override
  String get locationPermissionPermanentlyDenied =>
      'Standortberechtigung dauerhaft verweigert.';

  @override
  String get missingDestCoords =>
      'Alarm kann nicht starten: Es fehlen die Zielkoordinaten.';

  @override
  String wakeUpApproaching(String stop) {
    return 'Aufwachen! Du bist gleich in $stop!';
  }

  @override
  String get serviceBusyTryAgain =>
      'Der Dienst ist gerade ausgelastet. Versuch es noch einmal oder tippe mehr Zeichen ein.';

  @override
  String get serviceBusyPleaseTryAgain =>
      'Der Dienst ist gerade ausgelastet. Bitte versuch es noch einmal.';

  @override
  String get locationNotAvailable => 'Standort nicht verfügbar.';

  @override
  String get noRoutesFound => 'Keine Verbindungen gefunden.';

  @override
  String get noRoutesFoundBusy =>
      'Keine Verbindungen gefunden. Der Dienst ist vielleicht gerade ausgelastet – bitte versuch es noch einmal.';

  @override
  String get requestTimedOut =>
      'Zeitüberschreitung bei der Anfrage. Bitte versuch es noch einmal.';

  @override
  String get serviceBusyMoment =>
      'Der Dienst ist gerade ausgelastet. Bitte versuch es gleich noch einmal.';

  @override
  String get weakGps => '⚠️ Schwaches GPS';

  @override
  String get planJourney => 'Fahrt planen';

  @override
  String get tripTime => 'Fahrtzeit';

  @override
  String get now => 'Jetzt';

  @override
  String get currentLocation => 'Aktueller Standort';

  @override
  String get fromStationOrAddress => 'Start: Haltestelle oder Adresse...';

  @override
  String get toStationOrAddress => 'Ziel: Haltestelle oder Adresse...';

  @override
  String get stationOrAddress => 'Haltestelle oder Adresse...';

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
  String get findRoutes => 'Verbindungen suchen';

  @override
  String get favorites => 'Favoriten';

  @override
  String get add => 'Hinzufügen';

  @override
  String get frequentJourneys => 'Häufige Fahrten';

  @override
  String fromStation(String station) {
    return 'Ab $station';
  }

  @override
  String couldNotLoadMoreRoutes(String error) {
    return 'Weitere Verbindungen konnten nicht geladen werden: $error';
  }

  @override
  String couldNotRefreshRoutes(String error) {
    return 'Verbindungen konnten nicht aktualisiert werden: $error';
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
  String get noIntermediateStops => 'Keine Infos zu Zwischenhalten.';

  @override
  String getOffAtPlatform(String station, String platform) {
    return 'Aussteigen in $station (Gl. $platform)';
  }

  @override
  String getOffAt(String station) {
    return 'Aussteigen in $station';
  }

  @override
  String get station => 'Haltestelle';

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
  String get previous => 'FRÜHERE';

  @override
  String get dep => 'ABF';

  @override
  String get arr => 'ANK';

  @override
  String get passenger => 'FAHRGAST';

  @override
  String get walk => 'ZU FUSS';

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
  String get noSecureMessagesYet => 'Noch keine sicheren Nachrichten.';

  @override
  String get useImage => 'Bild verwenden';

  @override
  String get saySomething => 'Schreib etwas...';

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
  String get changeTicket => 'Ticket wechseln';

  @override
  String get addTicket => 'Ticket hinzufügen';

  @override
  String get selectImageFromGallery => 'Bild aus der Galerie wählen';

  @override
  String get previousSearches => 'Letzte Suchen';

  @override
  String get clearHistory => 'Verlauf löschen';

  @override
  String get confirmClearHistory =>
      'Möchtest du deinen bisherigen Suchverlauf wirklich löschen?';

  @override
  String get searchHistoryCleared => 'Suchverlauf gelöscht.';

  @override
  String get myTicket => 'Mein Ticket';

  @override
  String get generatingStyledQr => 'Stilisierter QR-Code wird erstellt...';

  @override
  String get styledFromOriginalTicketQrPattern =>
      'Erstellt aus dem QR-Muster deines Originaltickets';

  @override
  String get tapForFullscreen => 'Für Vollbild tippen';

  @override
  String get tapForFullscreenHoldForHistory =>
      'Für Vollbild tippen • Für Verlauf gedrückt halten';

  @override
  String get showOriginalTicket => 'Originalticket anzeigen';

  @override
  String get showStyledQr => 'Stilisierten QR-Code anzeigen';

  @override
  String get savedLocallyCloudUploadFailed =>
      'Lokal gespeichert. Der Cloud-Upload ist fehlgeschlagen.';

  @override
  String get couldNotIsolateQrBounds =>
      'Der QR-Bereich ließ sich nicht abgrenzen. Stattdessen wird das ganze Bild stilisiert.';

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
  String get wakeAlarmTracking => 'Deine Fahrt wird verfolgt...';

  @override
  String get alternative => 'Alternative';

  @override
  String get routeLabel => 'Verbindung';

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
    return '(+$minutes Min.)';
  }

  @override
  String switchPlatform(String fromPlatform, String toPlatform) {
    return 'Von $fromPlatform zu $toPlatform wechseln';
  }

  @override
  String waitAt(String place) {
    return 'Warten an $place';
  }

  @override
  String transferTo(String destination) {
    return 'Umsteigen nach $destination';
  }

  @override
  String get waitForConnection => 'Auf den Anschluss warten';

  @override
  String walkTo(String destination) {
    return 'Zu Fuß nach $destination';
  }

  @override
  String get walkToDestination => 'Zu Fuß zum Ziel';

  @override
  String get walkLabel => 'Fußweg';

  @override
  String atPlatform(String platform) {
    return 'an $platform';
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
  String get searchStationName => 'Haltestelle suchen';

  @override
  String get searchFriendUsername => 'Benutzernamen suchen';

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
      'Diese Aktion lässt sich nicht rückgängig machen. Alle deine Daten werden dauerhaft gelöscht.';

  @override
  String get enterPasswordToConfirm =>
      'Gib zur Bestätigung bitte dein Passwort ein:';

  @override
  String get deleteForever => 'Endgültig löschen';

  @override
  String get appName => 'Trans';

  @override
  String get privacy => 'Datenschutz';

  @override
  String get ghostMode => 'Ghost-Modus';

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
      'Das überschreibt deine globale Stufe nur für diesen Freund.';

  @override
  String get useGlobalSignal => 'Globale Stufe verwenden';

  @override
  String get friendLocation => 'Standort';

  @override
  String get darkMode => 'Dunkelmodus';

  @override
  String get syncedWithSystem => 'Mit dem System synchronisiert';

  @override
  String get systemSyncActive =>
      'System-Sync aktiv. Zum Deaktivieren gedrückt halten.';

  @override
  String get systemSyncEnabled => 'System-Sync aktiviert';

  @override
  String get manualModeEnabled => 'Manueller Modus aktiviert';

  @override
  String get deutschlandTicketMode => 'Deutschlandticket-Modus';

  @override
  String get onlyLocalTransport => 'Nur Nah- und Regionalverkehr';

  @override
  String get appearance => 'Erscheinungsbild';

  @override
  String get themeColor => 'Akzentfarbe';

  @override
  String get showTrainNumbers => 'Zugnummern anzeigen';

  @override
  String get displayTripIds => 'Fahrt-IDs anzeigen (z. B. RE1 (12345))';

  @override
  String get notificationsAndHaptics => 'Benachrichtigungen & Haptik';

  @override
  String get alarmTrigger => 'Alarm auslösen';

  @override
  String get alertAtDestination => 'Am Ziel alarmieren';

  @override
  String alertStopsBefore(String count) {
    return '$count Haltestellen vorher alarmieren';
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
    return 'Benachrichtigen bei $threshold $remaining';
  }

  @override
  String get alarmSound => 'Alarmton';

  @override
  String get previewSound => 'Ton anhören';

  @override
  String get wakeAlarmPreviewTitle => 'Weckalarm-Vorschau';

  @override
  String get wakeAlarmPreviewBody => 'So wird dein Weckalarm klingen.';

  @override
  String get alarmPattern => 'Alarmmuster';

  @override
  String get ofLegCovered => 'der Strecke zurückgelegt';

  @override
  String get fromTarget => 'bis zum Ziel';

  @override
  String get fivePercentRemaining => '5 % übrig';

  @override
  String get tenPercentRemaining => '10 % übrig';

  @override
  String get fixed500m => 'Feste 500 m';

  @override
  String get vibrationIntensity => 'Vibrationsstärke';

  @override
  String get alwaysWakeMe => 'Immer wecken';

  @override
  String get turnOnAlarmDefault =>
      'Alarm für jede Fahrt automatisch aktivieren';

  @override
  String get dataAndPrivacy => 'Daten & Datenschutz';

  @override
  String get clearSearchHistory => 'Suchverlauf löschen';

  @override
  String get dataSourceAdvanced => 'Datenquelle (erweitert)';

  @override
  String get transportApi => 'Transport-API';

  @override
  String selectedApiMode(String mode) {
    return 'Ausgewählt: $mode';
  }

  @override
  String get autoRecommended => 'Automatisch (empfohlen)';

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
      'Profil aktualisiert! Wenn du deine E-Mail geändert hast, prüfe bitte dein Postfach.';

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
      'Bevor die neue Adresse aktiv wird, schicken wir dir einen Bestätigungslink.';

  @override
  String get passwordChangeHint => 'Wähle ein neues Passwort für dein Konto.';

  @override
  String get confirmPassword => 'Passwort bestätigen';

  @override
  String get passwordsDoNotMatch => 'Die Passwörter stimmen nicht überein.';

  @override
  String get enterValidEmail => 'Gib eine gültige E-Mail-Adresse ein.';

  @override
  String get fillRequiredFields => 'Bitte fülle die erforderlichen Felder aus.';

  @override
  String get usernameUpdated => 'Benutzername aktualisiert.';

  @override
  String get emailUpdateSent =>
      'Prüfe deine E-Mails, um die Adressänderung zu bestätigen.';

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
      'Gib deine E-Mail-Adresse ein, um einen Link zum Zurücksetzen des Passworts zu erhalten.';

  @override
  String get passwordResetEmailSent =>
      'E-Mail zum Zurücksetzen gesendet (falls ein Konto existiert).';

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
    return 'Abfahrten ab $stopName';
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
      'Halte eine Haltestelle gedrückt, um alle Abfahrten des Tages zu sehen.';

  @override
  String get connectionSaved => 'Verbindung gespeichert';

  @override
  String get connectionUnsaved => 'Verbindung nicht mehr gespeichert';

  @override
  String get savedRouteDeleted => 'Gespeicherte Verbindung gelöscht';

  @override
  String get savedRoutesTitle => 'Gespeicherte Verbindungen';

  @override
  String get savedRoutesAutoDelete => '(werden 24 Std. nach Ankunft gelöscht)';

  @override
  String get noRecentRoutesYet => 'Noch keine letzten Verbindungen';

  @override
  String wakeAlertSetFor(String stop) {
    return 'Weckalarm für $stop gesetzt';
  }

  @override
  String leaveInMinutesFor(String minutes, String destination) {
    return 'In $minutes Min. losgehen Richtung $destination';
  }

  @override
  String leaveRemindersSummary(String summary) {
    return 'Erinnerungen zum Losgehen: $summary';
  }

  @override
  String get leaveRemindersNone => 'keine';

  @override
  String get leaveSoonTitle => 'Bald losgehen';

  @override
  String leaveSoonBody(String minutes, String from, String to, String time) {
    return 'Noch $minutes Min. bis $from → $to ($time)';
  }

  @override
  String get exactAlarmsBlocked =>
      'Android hat exakte Alarme für diese Erinnerung blockiert. Aktiviere für Trans die Berechtigung „Wecker und Erinnerungen“, damit die Erinnerungen zuverlässig kommen.';

  @override
  String couldNotOpen(String label) {
    return '$label konnte nicht geöffnet werden.';
  }

  @override
  String get searchThisConnectionIn => 'Diese Verbindung suchen in';

  @override
  String platformShort(String platform) {
    return 'Gl. $platform';
  }

  @override
  String customSoundSet(String label) {
    return 'Eigener Alarmton auf „$label“ gesetzt. Tippe in der Auswahl auf das Papierkorb-Symbol, um ihn zu entfernen.';
  }

  @override
  String get customSoundRemoved => 'Eigener Alarmton entfernt.';

  @override
  String couldNotRemoveCustomSound(String error) {
    return 'Der eigene Ton konnte nicht entfernt werden: $error';
  }

  @override
  String couldNotImportAudioReason(String error) {
    return 'Diese Audiodatei konnte nicht importiert werden: $error';
  }

  @override
  String get couldNotImportAudio =>
      'Diese Audiodatei konnte nicht importiert werden.';

  @override
  String get addCustomAudio => 'Eigenen Ton hinzufügen...';

  @override
  String couldNotSaveThemeColor(String error) {
    return 'Diese Akzentfarbe konnte nicht gespeichert werden: $error';
  }

  @override
  String get liveBuses => 'Busse live';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get compass => 'Kompass';

  @override
  String get recenter => 'Zentrieren';

  @override
  String get bike => 'RAD';

  @override
  String get useAppDefault => 'App-Standard verwenden';

  @override
  String get departureTimeLabel => 'Abfahrtszeit';

  @override
  String get arrivalTimeLabel => 'Ankunftszeit';

  @override
  String get applyToThisRoutesView => 'Auf diesen Tab anwenden';

  @override
  String get walkingSpeedLabel => 'Gehgeschwindigkeit';

  @override
  String get minimumTransferTimeLabel => 'Mindestumsteigezeit';

  @override
  String get transferPaddingLabel => 'Umsteigepuffer';

  @override
  String get maximumWalkingTimeLabel => 'Maximale Gehzeit';

  @override
  String get sortSheetEarliestDepHint =>
      'Ändert die Abfahrtszeit nur für diesen Tab.';

  @override
  String get sortSheetEarliestArrHint =>
      'Ändert die Ankunftszeit nur für diesen Tab.';

  @override
  String get sortSheetFastestHint =>
      'Passe die Gehgeschwindigkeit an, damit dieser Tab insgesamt schnellere Verbindungen bevorzugt.';

  @override
  String get sortSheetLeastTransfersHint =>
      'Mehr Umsteigepuffer, damit dieser Tab Verbindungen mit entspannteren Umstiegen bevorzugt.';

  @override
  String get sortSheetLeastWaitHint =>
      'Passe den Umsteigepuffer an, damit dieser Tab kürzere oder längere Wartezeiten bevorzugt.';

  @override
  String get sortSheetLeastWalkingHint =>
      'Begrenze die Gehzeit nur für diesen Tab, ohne die App-Einstellungen zu ändern.';
}
