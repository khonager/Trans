import 'package:flutter/material.dart';

/// Stable IDs preserve progress when lessons are translated or reordered.
class TutorialLesson {
  final String id;
  final String group;
  final List<String> english;
  final List<String> german;
  const TutorialLesson(this.id, this.group, this.english, this.german);
  List<String> copy(bool isGerman) => isGerman ? german : english;
}

class TutorialGroup {
  final String id;
  final String english;
  final String german;
  final IconData icon;
  const TutorialGroup(this.id, this.english, this.german, this.icon);
  String title(bool isGerman) => isGerman ? german : english;
}

const tutorialGroups = <TutorialGroup>[
  TutorialGroup("plan", "Plan your journey", "Reise planen", Icons.route),
  TutorialGroup("ride", "Travel with confidence", "Entspannt unterwegs",
      Icons.directions_transit),
  TutorialGroup(
      "maps", "Explore the map", "Karten entdecken", Icons.map_outlined),
  TutorialGroup("social", "Travel with friends", "Mit Freunden reisen",
      Icons.people_outline),
  TutorialGroup("tickets", "Keep your ticket handy", "Ticket griffbereit",
      Icons.confirmation_number_outlined),
  TutorialGroup("settings", "Make Trans yours", "Trans anpassen", Icons.tune),
];

const tutorialLessons = <TutorialLesson>[
  TutorialLesson("search", "plan", [
    "Find your first route",
    "Search between stations or addresses, or use your current location as the start.",
    "Open Routes. Choose From and To from the suggestions, then tap Find Routes. Use the swap arrows for the return trip and refresh location if your starting point is out of date.",
    "Find a bus from where you are to a café without knowing the nearest stop."
  ], [
    "Die erste Route finden",
    "Suche zwischen Haltestellen oder Adressen oder starte an deinem aktuellen Standort.",
    "Öffne Routen. Wähle Start und Ziel aus den Vorschlägen und tippe auf Routen suchen. Die Pfeile tauschen Start und Ziel; mit Standort aktualisieren erneuerst du deinen Startpunkt.",
    "Finde einen Bus von deinem Standort zu einem Café, ohne die nächste Haltestelle zu kennen."
  ]),
  TutorialLesson("time", "plan", [
    "Departure and arrival times",
    "Plan for now, a future departure, or a deadline at your destination.",
    "Tap Trip Time in the route planner. Set the date and time and choose Depart at or Arrive by, then search again.",
    "Use Arrive by to reach an appointment before 09:00."
  ], [
    "Abfahrt und Ankunft planen",
    "Plane für jetzt, eine spätere Abfahrt oder eine feste Ankunftszeit.",
    "Tippe in der Planung auf die Reisezeit. Wähle Datum und Uhrzeit sowie Abfahrt oder Ankunft und suche erneut.",
    "Wähle Ankunft, um vor 09:00 Uhr bei einem Termin zu sein."
  ]),
  TutorialLesson("sort", "plan", [
    "Compare and tune results",
    "Sort connections by departure, arrival, duration, transfers, waiting, or walking.",
    "Choose a sorting option in the results. Double-tap a sorting option to change the time, walking speed, transfer buffer, or walking limit for this results tab. Hold and drag sorting options to reorder them. Use Load Earlier or Load Later for more departures.",
    "Compare the fastest connection with a slower one that has fewer changes."
  ], [
    "Ergebnisse vergleichen und anpassen",
    "Sortiere nach Abfahrt, Ankunft, Dauer, Umstiegen, Wartezeit oder Fußweg.",
    "Wähle eine Sortierung in den Ergebnissen. Tippe eine Sortierung doppelt an, um Zeit, Gehgeschwindigkeit, Umstiegspuffer oder Fußweglimit für diesen Ergebnis-Tab zu ändern. Halte und ziehe Sortierungen, um sie neu anzuordnen. Lade frühere oder spätere Verbindungen nach.",
    "Vergleiche die schnellste Verbindung mit einer langsameren ohne viele Umstiege."
  ]),
  TutorialLesson("local", "plan", [
    "Deutschlandticket mode",
    "This search filter restricts results to local and regional transport; it does not buy or validate a ticket.",
    "In Settings, enable Deutschlandticket Mode, then run your route search. Check the operator’s ticket conditions for the connection you choose.",
    "Plan a regional trip while excluding long-distance trains."
  ], [
    "Deutschlandticket-Modus",
    "Dieser Suchfilter beschränkt Ergebnisse auf Nah- und Regionalverkehr; er kauft oder prüft kein Ticket.",
    "Aktiviere den Deutschlandticket-Modus in den Einstellungen und suche erneut. Prüfe beim Verkehrsunternehmen die Ticketbedingungen deiner Verbindung.",
    "Plane eine Regionalfahrt ohne Fernverkehrszüge."
  ]),
  TutorialLesson("favorites", "plan", [
    "Favorite places and friends",
    "Favorites are shortcuts to places or friends you visit often.",
    "In Routes, expand Favorites and tap Add. Choose a station or friend, give it a label and icon, and save. Tap a favorite to use it; long-press it to update or delete it.",
    "Save Home, Work, or a friend so you do not need to type the destination each time."
  ], [
    "Lieblingsorte und Freunde",
    "Favoriten sind Abkürzungen zu häufig besuchten Orten oder Freunden.",
    "Klappe in Routen die Favoriten auf und tippe auf Hinzufügen. Wähle eine Station oder einen Freund, vergib Name und Symbol und speichere. Tippe einen Favoriten zur Verwendung an; halte ihn zum Ändern oder Löschen gedrückt.",
    "Speichere Zuhause, Arbeit oder einen Freund, um das Ziel nicht jedes Mal einzutippen."
  ]),
  TutorialLesson("history", "plan", [
    "Recent and frequent journeys",
    "Your search history makes repeat journeys easier to find.",
    "On Routes, switch between Frequent and Recent and select an entry to reuse it. Clear Search History in Settings removes your recent searches.",
    "Repeat yesterday’s commute or find a destination you searched for last week."
  ], [
    "Letzte und häufige Fahrten",
    "Der Suchverlauf erleichtert wiederkehrende Fahrten.",
    "Wechsle in Routen zwischen häufigen und letzten Fahrten und wähle einen Eintrag erneut aus. In den Einstellungen kannst du den Suchverlauf löschen.",
    "Wiederhole den Arbeitsweg von gestern oder finde ein kürzlich gesuchtes Ziel."
  ]),
  TutorialLesson("save", "plan", [
    "Save a connection",
    "Saved routes keep a specific connection ready to reopen, rather than just remembering its destination.",
    "Use the save control on a connection. Find it under Saved routes on the planner and tap to reopen before it is completed. Remove it when no longer needed; saved routes expire 24 hours after arrival.",
    "Keep tomorrow’s chosen train ready while comparing other routes."
  ], [
    "Eine Verbindung speichern",
    "Gespeicherte Routen halten eine konkrete Verbindung bereit, nicht nur ihr Ziel.",
    "Nutze das Speichern-Symbol einer Verbindung. Unter gespeicherten Routen kannst du sie vor Abschluss erneut öffnen. Entferne sie bei Bedarf; 24 Stunden nach Ankunft werden gespeicherte Routen automatisch gelöscht.",
    "Halte den ausgewählten Zug für morgen bereit, während du andere Routen vergleichst."
  ]),
  TutorialLesson("leave", "plan", [
    "Leave reminders",
    "A saved future connection can remind you before it is time to leave.",
    "Long-press an upcoming saved route to show reminder choices. Select the lead times you want; tap selected times again to turn them off. Allow notifications and, if Android asks, alarms and reminders.",
    "Get a reminder before leaving home for your train."
  ], [
    "Abfahrts-Erinnerungen",
    "Eine gespeicherte zukünftige Verbindung kann dich vor dem Aufbruch erinnern.",
    "Halte eine bevorstehende gespeicherte Route gedrückt, um Erinnerungszeiten zu wählen. Tippe gewählte Zeiten erneut an, um sie zu deaktivieren. Erlaube Benachrichtigungen und gegebenenfalls unter Android Alarme und Erinnerungen.",
    "Lass dich erinnern, bevor du zum Zug aufbrechen musst."
  ]),
  TutorialLesson("details", "ride", [
    "Read your itinerary",
    "Journey details bring together walking, riding, waiting, transfers, platforms, and available delay or cancellation information.",
    "Open a connection and expand a ride card for intermediate stops. Compare planned and updated times and check the boarding platform. Long-press the ride heading to open the full trip beyond your own section.",
    "Check where to change trains and whether a delay affects the connection."
  ], [
    "Den Reiseverlauf lesen",
    "Reisedetails zeigen Fußwege, Fahrten, Wartezeiten, Umstiege, Gleise sowie verfügbare Verspätungen und Ausfälle.",
    "Öffne eine Verbindung und klappe eine Fahrt für Zwischenhalte auf. Vergleiche geplante und aktualisierte Zeiten und prüfe das Abfahrtsgleis. Halte die Fahrtüberschrift gedrückt, um die gesamte Fahrt über deinen Abschnitt hinaus zu sehen.",
    "Prüfe den Umstiegsort und ob eine Verspätung deinen Anschluss betrifft."
  ]),
  TutorialLesson("departures", "ride", [
    "Departure boards",
    "A stop’s departure board shows other services available that day.",
    "Long-press a stop in the itinerary or a station suggestion to open departures. Use the date, platform, and service-day filters where available; use the top and bottom controls to move through the list.",
    "See what else leaves your platform after a missed bus."
  ], [
    "Abfahrtstafeln",
    "Die Abfahrtstafel einer Haltestelle zeigt weitere Fahrten für den Tag.",
    "Halte einen Halt im Reiseverlauf oder einen Stationsvorschlag gedrückt. Nutze verfügbare Filter für Datum, Gleis und Verkehrstag sowie die Sprünge zum Anfang und Ende der Liste.",
    "Finde nach einem verpassten Bus weitere Abfahrten am selben Steig."
  ]),
  TutorialLesson("alternatives", "ride", [
    "Alternative connections",
    "Alternatives help you adjust a journey from a boarding or intermediate stop.",
    "Open a ride card and tap Alt, or use an available alternative control at a stop. Compare earlier or later options and choose one. The Back to … route button returns to the original plan after selecting an alternative.",
    "Switch to another connection when a transfer becomes inconvenient."
  ], [
    "Alternative Verbindungen",
    "Alternativen passen deine Reise ab einem Einstiegs- oder Zwischenhalt an.",
    "Öffne eine Fahrt und tippe auf Alt oder nutze die Alternative an einem Halt. Vergleiche frühere und spätere Optionen. Nach einer Auswahl führt Zurück zur … Route zum ursprünglichen Plan zurück.",
    "Wechsle die Verbindung, wenn ein Umstieg unpraktisch wird."
  ]),
  TutorialLesson("onboard", "ride", [
    "Already on this bus?",
    "Onboard options look at useful changes from the remaining stops of your current service.",
    "Long-press Alt on the ride card, or choose I’m on this bus in the alternatives view. Check or change the next stop, then compare staying aboard with getting off at a later stop. Lines you can take lists other useful services when available.",
    "Check whether staying on your bus or changing ahead gets you there sooner."
  ], [
    "Schon in diesem Bus?",
    "Optionen an Bord prüfen sinnvolle Umstiege an den verbleibenden Haltestellen.",
    "Halte Alt in der Fahrtkarte gedrückt oder wähle in den Alternativen Ich bin in diesem Bus. Prüfe oder ändere den nächsten Halt und vergleiche Weiterfahren mit späterem Aussteigen. Nutzbare Linien erscheinen, wenn verfügbar.",
    "Prüfe, ob Weiterfahren oder ein Umstieg unterwegs schneller ist."
  ]),
  TutorialLesson("extend", "ride", [
    "Add another leg to your journey",
    "You can append a new section to an open journey.",
    "Scroll to the bottom of an active route and tap Add to route (+). Search for your next destination and choose a connection to extend the itinerary.",
    "Plan a stop for lunch and then continue to another town."
  ], [
    "Eine Reise verlängern",
    "Du kannst einer geöffneten Reise einen weiteren Abschnitt hinzufügen.",
    "Scrolle ans Ende einer aktiven Route und tippe auf Route hinzufügen (+). Suche das nächste Ziel und wähle eine Verbindung zur Erweiterung des Reiseverlaufs.",
    "Plane einen Zwischenstopp zum Mittagessen und fahre danach in eine andere Stadt."
  ]),
  TutorialLesson("wake", "ride", [
    "Wake me before my stop",
    "Wake alarms use your location to alert you near a selected stop.",
    "Open a ride and tap Wake Me. Allow location and notification access. For a particular intermediate stop, long-press its alarm control. Tap an active alarm again to turn it off. Weak GPS can affect the alert.",
    "Read or rest on a long ride with an alert before your exit."
  ], [
    "Vor dem Ausstieg wecken",
    "Weckalarme nutzen deinen Standort, um dich nahe einem gewählten Halt zu benachrichtigen.",
    "Öffne eine Fahrt und tippe auf Wecken. Erlaube Standortzugriff und Benachrichtigungen. Für einen Zwischenhalt hältst du dessen Alarm-Symbol gedrückt. Tippe einen aktiven Alarm erneut an, um ihn auszuschalten. Schwaches GPS kann den Alarm beeinträchtigen.",
    "Lies oder ruhe dich während einer längeren Fahrt mit einem Alarm vor dem Ausstieg aus."
  ]),
  TutorialLesson("share", "ride", [
    "Share a route and check other planners",
    "A route ticket is a shareable picture of the itinerary, separate from your travel ticket.",
    "Use the copy control for a connection to copy its route ticket, then paste it into another app. Use the DB or RMV links in the results to search the connection in another planner.",
    "Send your travel plan to someone who is meeting you at the station."
  ], [
    "Eine Route teilen und anderswo prüfen",
    "Ein Routenticket ist ein teilbares Bild des Reiseplans, kein Fahrschein.",
    "Nutze das Kopieren-Symbol einer Verbindung und füge das Routenticket in einer anderen App ein. Über DB oder RMV in den Ergebnissen suchst du die Verbindung in einem anderen Planer.",
    "Schicke deinen Reiseplan an jemanden, der dich am Bahnhof abholt."
  ]),
  TutorialLesson("route_map", "maps", [
    "See your route on a map",
    "Route maps put the journey and individual travel sections into context.",
    "Open the map control for a route or ride; tap a walking section to see its map when available. Pan and zoom to inspect the path and nearby places.",
    "Understand the walk between your arrival stop and destination."
  ], [
    "Die Route auf der Karte sehen",
    "Routenkarten zeigen die Reise und einzelne Abschnitte räumlich.",
    "Öffne die Karte einer Route oder Fahrt; tippe auf einen Fußweg, um dessen Karte zu sehen, sofern verfügbar. Verschiebe und zoome die Karte, um den Weg zu prüfen.",
    "Orientiere dich beim Fußweg von der Ankunftshaltestelle zum Ziel."
  ]),
  TutorialLesson("live_map", "maps", [
    "Live buses and map controls",
    "The live map shows available vehicle information in the area; coverage depends on the data source.",
    "Long-press the Routes icon in the bottom navigation. Explore the map and select a vehicle for details. Use Refresh for new data, Recenter to return to your location, and Compass to adjust orientation.",
    "Look for services near you while waiting at a stop."
  ], [
    "Live-Busse und Kartensteuerung",
    "Die Live-Karte zeigt verfügbare Fahrzeuginformationen in der Umgebung; die Abdeckung hängt von der Datenquelle ab.",
    "Halte das Routen-Symbol in der unteren Navigation gedrückt. Erkunde die Karte und wähle ein Fahrzeug für Details. Nutze Aktualisieren für neue Daten, Zentrieren für deinen Standort und den Kompass für die Ausrichtung.",
    "Sieh beim Warten nach Fahrten in deiner Nähe."
  ]),
  TutorialLesson("account", "social", [
    "Sign in and manage your profile",
    "An account enables social features and supported syncing. Available sign-in providers depend on your platform.",
    "Open Settings to sign up or log in, or use an offered sign-in provider. In Profile, change your username, email, or password. Use Forgot Password if you cannot sign in.",
    "Choose a recognizable username so friends can find you."
  ], [
    "Anmelden und Profil verwalten",
    "Ein Konto ermöglicht soziale Funktionen und unterstützte Synchronisierung. Verfügbare Anmeldeanbieter hängen von der Plattform ab.",
    "Registriere dich in den Einstellungen oder melde dich an, auch über angebotene Anbieter. Im Profil änderst du Nutzername, E-Mail oder Passwort. Nutze Passwort vergessen, falls die Anmeldung nicht klappt.",
    "Wähle einen erkennbaren Nutzernamen, damit Freunde dich finden."
  ]),
  TutorialLesson("friends", "social", [
    "Add and manage friends",
    "Friend requests let both people agree to connect.",
    "Sign in, open Friends and add someone by username. Accept or decline incoming requests, or cancel a pending sent request. Open a friend’s actions to remove the friendship if needed.",
    "Connect with a travel companion before a shared trip."
  ], [
    "Freunde hinzufügen und verwalten",
    "Freundschaftsanfragen lassen beide Seiten einer Verbindung zustimmen.",
    "Melde dich an, öffne Freunde und suche nach einem Nutzernamen. Nimm eingehende Anfragen an oder lehne sie ab; gesendete offene Anfragen kannst du zurückziehen. Über die Aktionen eines Freundes entfernst du die Freundschaft.",
    "Verbinde dich vor einer gemeinsamen Reise mit deiner Begleitung."
  ]),
  TutorialLesson("privacy", "social", [
    "Choose what you share",
    "Privacy levels range from 0 (share nothing) to 8 (also share labeled favorites). Higher levels expose more detail.",
    "In Settings, open Privacy Level and its guide. Levels 1–5 add line, journey times, destination, itinerary, then progress; 6 adds exact location during a detected journey, 7 keeps the latest location available, and 8 adds favorites. Choose only what you want to share.",
    "Share your arrival plan without choosing continuous location availability."
  ], [
    "Festlegen, was du teilst",
    "Datenschutzstufen reichen von 0 (nichts teilen) bis 8 (auch benannte Favoriten). Höhere Stufen zeigen mehr Details.",
    "Öffne in den Einstellungen die Datenschutzstufe und ihre Erklärung. Stufen 1–5 ergänzen Linie, Reisezeiten, Ziel, Verlauf und Fortschritt; 6 ergänzt den genauen Standort während einer erkannten Reise, 7 hält den letzten Standort bereit, 8 ergänzt Favoriten. Teile nur, was du möchtest.",
    "Teile deinen Ankunftsplan, ohne deinen Standort ständig verfügbar zu machen."
  ]),
  TutorialLesson("friend_privacy", "social", [
    "Set privacy for one friend",
    "A friend-specific privacy level overrides your global level for that person.",
    "Open the friend’s actions and choose Privacy Level. Select a level or Use global level to remove the override. Review this alongside your global setting.",
    "Share more detail with a close companion than with other contacts."
  ], [
    "Datenschutz für einzelne Freunde",
    "Die Datenschutzstufe eines Freundes überschreibt deine globale Stufe nur für diese Person.",
    "Öffne die Aktionen des Freundes und wähle Datenschutzstufe. Wähle eine Stufe oder die globale Einstellung, um die Ausnahme zu entfernen. Prüfe sie zusammen mit deiner allgemeinen Einstellung.",
    "Teile mit einer engen Begleitung mehr Details als mit anderen Kontakten."
  ]),
  TutorialLesson("friend_route", "social", [
    "Find or travel to a friend",
    "Friend location, route, progress, and favorite views depend on what that friend shares with you.",
    "Open a friend’s actions and choose Location or Route when available. Use a shared favorite as a destination if offered. Check how old the location is before planning a journey there.",
    "Meet a friend at their shared location without exchanging an address."
  ], [
    "Freunde finden oder besuchen",
    "Standort, Route, Fortschritt und Favoriten eines Freundes hängen von dessen Freigaben ab.",
    "Öffne die Aktionen eines Freundes und wähle, falls verfügbar, Standort oder Route. Nutze angebotene geteilte Favoriten als Ziel. Prüfe vor der Planung, wie alt der Standort ist.",
    "Triff einen Freund am geteilten Standort, ohne eine Adresse auszutauschen."
  ]),
  TutorialLesson("together", "social", [
    "Plan a journey together",
    "Joint planning compares ways for you and a companion to travel toward a destination together.",
    "Tap or swipe the handle beside Plan Journey to enable joint planning. Select a friend or enter their start, set the destination, and search. Compare the shared plans. The togetherness balance in Settings adjusts the preference for time together versus trip time.",
    "Find where to join up when you start from different neighborhoods."
  ], [
    "Eine gemeinsame Reise planen",
    "Gemeinsame Planung vergleicht Möglichkeiten, mit einer Begleitung zum Ziel zu reisen.",
    "Tippe oder wische am Griff neben Reise planen, um gemeinsam zu planen. Wähle einen Freund oder dessen Start, setze das Ziel und suche. Vergleiche die Pläne. Die Balance in den Einstellungen gewichtet gemeinsame Zeit gegenüber Reisezeit.",
    "Finde einen Treffpunkt unterwegs, wenn ihr aus verschiedenen Vierteln startet."
  ]),
  TutorialLesson("chat", "social", [
    "Private and line chats",
    "Private chats are for conversations with a friend; line chats are shared discussions about a service.",
    "Choose Chat in a friend’s actions for a private conversation. In an expanded ride card, tap the chat icon for that line. Write your message and send; use image attachment controls where offered.",
    "Message your friend privately, or discuss a disruption in the line chat."
  ], [
    "Private Chats und Linienchats",
    "Private Chats sind Gespräche mit Freunden; Linienchats sind gemeinsame Unterhaltungen zu einer Linie.",
    "Wähle Chat bei einem Freund für ein privates Gespräch. Tippe in einer aufgeklappten Fahrt auf das Chat-Symbol für die Linie. Schreibe und sende deine Nachricht; nutze angebotene Bildanhänge.",
    "Schreibe deinem Freund privat oder tausche dich im Linienchat zu einer Störung aus."
  ]),
  TutorialLesson("safety", "social", [
    "Report, block, and unblock",
    "Reporting flags a problem; blocking controls unwanted contact.",
    "Use a friend’s report or block action, or long-press a line-chat message for message actions. Review blocked users in Settings and choose Unblock if you want to reverse a block.",
    "Stop unwanted contact and report an abusive message."
  ], [
    "Melden, blockieren und entsperren",
    "Meldungen weisen auf Probleme hin; Blockieren begrenzt unerwünschten Kontakt.",
    "Nutze Melden oder Blockieren bei einem Freund oder halte eine Nachricht im Linienchat für Aktionen gedrückt. In den Einstellungen kannst du blockierte Nutzer prüfen und wieder entsperren.",
    "Beende unerwünschten Kontakt und melde eine beleidigende Nachricht."
  ]),
  TutorialLesson("ticket_add", "tickets", [
    "Add and crop a ticket",
    "The ticket panel stores an image of a ticket you already have; Trans does not sell tickets.",
    "Open the ticket panel and tap Add Ticket. Select an image, review the detected QR crop, or choose Crop / Edit to adjust it. Confirm the image. Sign-in allows a cloud upload; a local-save message may indicate upload failure.",
    "Keep a screenshot of your existing travel pass easy to reach."
  ], [
    "Ticket hinzufügen und zuschneiden",
    "Das Ticketfach speichert ein Bild eines vorhandenen Tickets; Trans verkauft keine Fahrscheine.",
    "Öffne das Ticketfach und tippe auf Ticket hinzufügen. Wähle ein Bild, prüfe den erkannten QR-Ausschnitt oder passe ihn über Zuschneiden / Bearbeiten an. Bestätige das Bild. Mit Anmeldung ist ein Cloud-Upload möglich; ein Hinweis auf lokale Speicherung kann einen Uploadfehler anzeigen.",
    "Halte einen Screenshot deines vorhandenen Fahrscheins griffbereit."
  ]),
  TutorialLesson("ticket_show", "tickets", [
    "Show your ticket quickly",
    "The ticket image can open full-screen, with an optional styled QR view when available.",
    "Tap the panel handle to open it, then tap the ticket to show it full-screen. Tap again to close. Switch between Show Original Ticket and Show Styled QR when those controls are available.",
    "Open the original ticket image quickly during an inspection."
  ], [
    "Ticket schnell vorzeigen",
    "Das Ticketbild lässt sich im Vollbild öffnen; ein gestalteter QR-Code ist verfügbar, wenn unterstützt.",
    "Tippe auf den Griff des Ticketfachs und dann auf das Ticket für Vollbild. Erneutes Tippen schließt es. Wechsle bei verfügbaren Schaltern zwischen Originalticket und gestaltetem QR-Code.",
    "Öffne bei einer Kontrolle schnell das Originalbild deines Tickets."
  ]),
  TutorialLesson("ticket_history", "tickets", [
    "Replace tickets and revisit history",
    "Ticket history helps manage previous images on supported non-web platforms.",
    "Use Change Ticket for a new image. Hold the displayed ticket to open history, then select an older ticket or use its rename and delete controls. On Android and iOS, replacing a ticket schedules a reminder for the next month.",
    "Replace a monthly pass while keeping an older image identifiable by name."
  ], [
    "Tickets ersetzen und Verlauf nutzen",
    "Auf unterstützten Plattformen außerhalb des Browsers verwaltet der Ticketverlauf frühere Bilder.",
    "Nutze Ticket ändern für ein neues Bild. Halte das angezeigte Ticket gedrückt, um den Verlauf zu öffnen. Wähle dort ein altes Ticket oder nutze Umbenennen und Löschen. Unter Android und iOS plant das Ersetzen eine Erinnerung für den nächsten Monat.",
    "Ersetze eine Monatskarte und erkenne ältere Bilder an ihrem Namen wieder."
  ]),
  TutorialLesson("ticket_dock", "tickets", [
    "Tuck the ticket panel away",
    "The ticket panel can be docked to free up space while you plan.",
    "Collapse the ticket panel, then hold its handle and drag it down to dock it. Hold the QR icon in the bottom navigation and drag upward to bring the panel back. A normal tap on the panel handle opens or closes the sheet.",
    "Make more room for route details, then bring your ticket back when needed."
  ], [
    "Das Ticketfach verstauen",
    "Du kannst das Ticketfach verstauen, um mehr Platz für die Planung zu haben.",
    "Klappe das Ticketfach zu, halte seinen Griff und ziehe ihn nach unten zum Verstauen. Halte das QR-Symbol in der unteren Navigation und ziehe es nach oben, um das Fach zurückzuholen. Einfaches Tippen öffnet oder schließt das Fach.",
    "Schaffe Platz für Reisedetails und hole das Ticket bei Bedarf zurück."
  ]),
  TutorialLesson("appearance", "settings", [
    "Colors, theme, language, and train numbers",
    "Appearance settings adapt the app to your preferences.",
    "In Settings, choose a theme color, switch dark mode or system synchronization, select English or German, and enable Show Train Numbers for trip IDs. Long-press the dark-mode control to change system synchronization.",
    "Use a dark interface at night and show train numbers to identify your service."
  ], [
    "Farben, Design, Sprache und Zugnummern",
    "Die Darstellung lässt sich an deine Wünsche anpassen.",
    "Wähle in den Einstellungen eine Farbe, Dunkelmodus oder Systemsynchronisierung sowie Deutsch oder Englisch. Aktiviere Zugnummern für Fahrtkennungen. Halte den Dunkelmodus-Schalter gedrückt, um die Systemsynchronisierung zu ändern.",
    "Nutze nachts ein dunkles Design und erkenne deinen Zug an seiner Nummer."
  ]),
  TutorialLesson("alarm_settings", "settings", [
    "Customize alarms and haptics",
    "Wake alarms and leave reminders have separate sound and vibration switches.",
    "In Notifications & Haptics, choose how many stops early to alert and the trigger threshold. Set a sound, import custom audio if supported, preview it, and adjust vibration pattern and intensity. Always Wake Me enables alarms by default for journeys.",
    "Choose an earlier wake alert and preview a sound you can recognize."
  ], [
    "Alarme und Vibration anpassen",
    "Weckalarme und Abfahrts-Erinnerungen haben getrennte Schalter für Ton und Vibration.",
    "Wähle unter Benachrichtigungen und Haptik den Vorlauf in Haltestellen und die Auslöseschwelle. Wähle oder importiere einen Ton, höre ihn vor und passe Vibrationsmuster und Stärke an. Immer wecken aktiviert Alarme standardmäßig für Reisen.",
    "Wähle einen früheren Weckalarm und teste einen gut erkennbaren Ton."
  ]),
  TutorialLesson("advanced", "settings", [
    "Advanced routing and data sources",
    "Advanced settings change routing assumptions and which transport sources are used.",
    "On builds with a visible version label, hold it in Settings for seven seconds to unlock advanced settings on this device. Review the source selection, minimum transfer time, extra buffer, transfer factor, walking and cycling speeds, walking limit, and walk/bike access before and after transit.",
    "Allow more transfer time or adjust walking assumptions to match your pace."
  ], [
    "Erweiterte Routenplanung und Datenquellen",
    "Erweiterte Einstellungen verändern Planungsannahmen und verwendete Verkehrsdatenquellen.",
    "Halte bei Builds mit sichtbarer Versionsnummer diese in den Einstellungen sieben Sekunden gedrückt, um erweiterte Einstellungen auf diesem Gerät freizuschalten. Prüfe Datenquellen, Mindestumstieg, Zusatzpuffer, Umstiegsfaktor, Geh- und Radgeschwindigkeit, Fußweglimit sowie Fuß- und Radwege vor und nach dem ÖPNV.",
    "Plane mehr Umstiegszeit ein oder passe Fußwege an dein Tempo an."
  ]),
  TutorialLesson("data", "settings", [
    "Account links and data controls",
    "Settings provides account linking and controls for your history and account.",
    "In Profile, use the Portfolio sign-in/link options if needed; the Trans Link Token can be pasted into Portfolio’s connected-app settings. Use Clear Search History, Log Out, or Delete Account for the corresponding action. Account deletion requires confirmation and is permanent.",
    "Clear old searches on a shared device or link your Portfolio account."
  ], [
    "Kontoverknüpfungen und Daten verwalten",
    "Die Einstellungen bieten Kontoverknüpfungen sowie Kontrolle über Verlauf und Konto.",
    "Nutze im Profil bei Bedarf die Portfolio-Anmeldung oder -Verknüpfung; das Trans-Link-Token lässt sich in Portfolios verbundenen Apps einfügen. Nutze Suchverlauf löschen, Abmelden oder Konto löschen für die jeweilige Aktion. Kontolöschung erfordert eine Bestätigung und ist endgültig.",
    "Lösche alte Suchen auf einem gemeinsam genutzten Gerät oder verbinde dein Portfolio-Konto."
  ]),
  TutorialLesson("updates", "settings", [
    "Release notes and this guide",
    "Release notes describe changes; the tutorial remains available whenever you want to revisit a feature.",
    "Tap the version label in Settings to read the changelog when shown. Open Tutorial from Settings to return here. Expand any lesson, try its steps if useful, and mark it learned. You can undo completion at any time; progress stays on this device.",
    "After an update, look for new features and return to the lessons you still want to explore."
  ], [
    "Versionshinweise und diese Anleitung",
    "Versionshinweise erklären Änderungen; die Anleitung bleibt jederzeit zum Nachlesen verfügbar.",
    "Tippe auf die sichtbare Versionsnummer in den Einstellungen für das Änderungsprotokoll. Über Tutorial kommst du hierher zurück. Öffne eine Lektion, probiere ihre Schritte bei Bedarf aus und markiere sie als gelernt. Du kannst das jederzeit rückgängig machen; der Fortschritt bleibt auf diesem Gerät.",
    "Sieh nach einem Update nach neuen Funktionen und kehre zu noch offenen Lektionen zurück."
  ]),
  TutorialLesson("tabs", "plan", [
    "Keep several routes open",
    "Route tabs let you keep different searches and selected journeys side by side.",
    "Tap a route tab to switch to it. Tap the active tab to expand or collapse its stack of journeys. Tap its × to close it; hold that × to close the other route tabs.",
    "Compare two destinations without losing your first search."
  ], [
    "Mehrere Routen offen halten",
    "Routen-Tabs halten verschiedene Suchen und ausgewählte Reisen nebeneinander bereit.",
    "Tippe auf einen Routen-Tab zum Wechseln. Tippe den aktiven Tab an, um seinen Stapel von Reisen auf- oder zuzuklappen. Mit × schließt du ihn; halte × gedrückt, um die anderen Routen-Tabs zu schließen.",
    "Vergleiche zwei Ziele, ohne deine erste Suche zu verlieren."
  ]),
  TutorialLesson("detection", "ride", [
    "Journey detection and live progress",
    "Trans can match your location to journeys you searched, opened, selected, or saved to recognize travel and update progress.",
    "Search for or open your intended connection and allow location access for the features you use. Check the displayed journey and progress against your actual service. What friends see is controlled by your privacy level; detection depends on location and route data.",
    "Let shared journey progress help a friend follow your approach during a trip."
  ], [
    "Reiseerkennung und Live-Fortschritt",
    "Trans kann deinen Standort mit gesuchten, geöffneten, ausgewählten oder gespeicherten Reisen abgleichen, um Fahrten zu erkennen und den Fortschritt zu aktualisieren.",
    "Suche oder öffne deine geplante Verbindung und erlaube den Standortzugriff für genutzte Funktionen. Vergleiche die angezeigte Reise und ihren Fortschritt mit deiner tatsächlichen Fahrt. Deine Datenschutzstufe bestimmt, was Freunde sehen; die Erkennung hängt von Standort- und Routendaten ab.",
    "Lass einen Freund während der Fahrt deinen geteilten Reisefortschritt verfolgen."
  ]),
  TutorialLesson("avatar", "social", [
    "Choose your profile emoji",
    "Your profile emoji helps friends recognize you in social views.",
    "Sign in and open Profile in Settings. Tap your avatar to choose an emoji, then check it in your profile.",
    "Use a recognizable emoji so your messages are easier to spot."
  ], [
    "Ein Profil-Emoji wählen",
    "Dein Profil-Emoji hilft Freunden, dich in sozialen Ansichten wiederzuerkennen.",
    "Melde dich an und öffne das Profil in den Einstellungen. Tippe auf deinen Avatar, wähle ein Emoji und prüfe es im Profil.",
    "Wähle ein erkennbares Emoji, damit deine Nachrichten leichter auffallen."
  ]),
  TutorialLesson("color", "settings", [
    "Choose a personal color",
    "Theme Color supports a custom color and checks color ownership for signed-in accounts.",
    "Open Theme Color in Settings and choose a color or enter a hex value. If the color is already claimed, choose another. Portfolio linking can connect color ownership across apps; follow the picker’s availability messages.",
    "Match Trans to a color you use for your profile."
  ], [
    "Eine persönliche Farbe wählen",
    "Die Designfarbe unterstützt eigene Farben und prüft bei angemeldeten Konten deren Zuordnung.",
    "Öffne die Designfarbe in den Einstellungen und wähle eine Farbe oder gib einen Hex-Wert ein. Ist sie schon vergeben, wähle eine andere. Die Portfolio-Verknüpfung kann Farbzuordnungen über Apps hinweg verbinden; beachte die Hinweise zur Verfügbarkeit.",
    "Passe Trans an die Farbe deines Profils an."
  ]),
];
