import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/journey_sharing.dart';

/// Opens the guided explanation for the Journey Signal privacy levels.
///
/// The guide deliberately uses lightweight UI previews instead of screenshots,
/// so it remains crisp at every display size and adds no image assets to the
/// installed app.
Future<int?> showJourneySignalTutorial(
  BuildContext context, {
  required int initialLevel,
}) {
  return showDialog<int?>(
    context: context,
    builder: (_) => JourneySignalTutorial(initialLevel: initialLevel),
  );
}

class JourneySignalTutorial extends StatefulWidget {
  final int initialLevel;

  const JourneySignalTutorial({super.key, required this.initialLevel});

  @override
  State<JourneySignalTutorial> createState() => _JourneySignalTutorialState();
}

class _JourneySignalTutorialState extends State<JourneySignalTutorial> {
  late final PageController _pageController;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = JourneySignalLevel.clamp(widget.initialLevel);
    _pageController = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    final copy = _JourneySignalTutorialCopy(isGerman: isGerman);
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: colors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: size.height * .86,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.effectiveSeed.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.cell_tower_rounded,
                      color: colors.effectiveSeed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.title,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 19,
                          ),
                        ),
                        Text(
                          copy.subtitle,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: colors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children:
                    List.generate(JourneySignalLevel.maximum + 1, (index) {
                  final isCurrent = index == _page;
                  final isPast = index < _page;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: EdgeInsets.only(
                        right: index == JourneySignalLevel.maximum ? 0 : 4,
                      ),
                      height: isCurrent ? 6 : 4,
                      decoration: BoxDecoration(
                        color: isCurrent || isPast
                            ? colors.effectiveSeed
                            : colors.divider,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: JourneySignalLevel.maximum + 1,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, level) => _TutorialPage(
                    level: level,
                    copy: copy,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _page == JourneySignalLevel.minimum
                        ? null
                        : () => _goToPage(_page - 1),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(copy.back),
                  ),
                  const Spacer(),
                  Text(
                    '${_page + 1} / ${JourneySignalLevel.maximum + 1}',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                  const Spacer(),
                  if (_page < JourneySignalLevel.maximum)
                    TextButton.icon(
                      onPressed: () => _goToPage(_page + 1),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(copy.next),
                    )
                  else
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(copy.done),
                    ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _page),
                  icon: const Icon(Icons.check),
                  label: Text(copy.useLevel(_page)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TutorialPage extends StatelessWidget {
  final int level;
  final _JourneySignalTutorialCopy copy;

  const _TutorialPage({required this.level, required this.copy});

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final details = copy.levelDetails(level);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: level == 0
                      ? colors.chipBg
                      : colors.effectiveSeed.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${copy.level} $level',
                  style: TextStyle(
                    color: level == 0
                        ? colors.textSecondary
                        : colors.effectiveSeed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  JourneySignalLevel.title(level, languageCode: languageCode),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            JourneySignalLevel.description(level, languageCode: languageCode),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          _SignalPreview(level: level, copy: copy),
          const SizedBox(height: 16),
          Text(
            copy.whyThisLevel,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            details.why,
            style: TextStyle(color: colors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.effectiveSeed.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.privacy_tip_outlined, color: colors.effectiveSeed),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    details.privacyNote,
                    style: TextStyle(
                      color: colors.textPrimary,
                      height: 1.3,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalPreview extends StatelessWidget {
  final int level;
  final _JourneySignalTutorialCopy copy;

  const _SignalPreview({required this.level, required this.copy});

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final items = copy.visibleItems(level);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.isDark ? Colors.black26 : colors.scaffoldBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined,
                  size: 18, color: colors.effectiveSeed),
              const SizedBox(width: 7),
              Text(
                copy.friendPreview,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Row(
              children: [
                Icon(Icons.visibility_off_outlined,
                    color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(copy.nothingVisible,
                    style: TextStyle(color: colors.textSecondary)),
              ],
            )
          else
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Icon(item.icon, size: 18, color: colors.effectiveSeed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.label,
                          style: TextStyle(color: colors.textPrimary)),
                    ),
                    Icon(Icons.check_circle,
                        size: 17, color: Colors.green.shade600),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VisibleItem {
  final IconData icon;
  final String label;

  const _VisibleItem(this.icon, this.label);
}

class _LevelDetails {
  final String why;
  final String privacyNote;

  const _LevelDetails({required this.why, required this.privacyNote});
}

class _JourneySignalTutorialCopy {
  final bool isGerman;

  const _JourneySignalTutorialCopy({required this.isGerman});

  String get title =>
      isGerman ? 'Reisesignal verstehen' : 'Understand Journey Signal';
  String get subtitle => isGerman
      ? 'Wähle genau, was Freunde sehen können.'
      : 'Choose exactly what friends can see.';
  String get level => isGerman ? 'Stufe' : 'Level';
  String get back => isGerman ? 'Zurück' : 'Back';
  String get next => isGerman ? 'Weiter' : 'Next';
  String get done => isGerman ? 'Fertig' : 'Done';
  String get whyThisLevel =>
      isGerman ? 'Wofür ist das?' : 'Why this level exists';
  String get friendPreview => isGerman
      ? 'Vorschau: Das sehen deine Freunde'
      : 'Preview: What your friends can see';
  String get nothingVisible =>
      isGerman ? 'Nichts wird geteilt.' : 'Nothing is shared.';

  String useLevel(int value) =>
      isGerman ? 'Stufe $value verwenden' : 'Use level $value';

  List<_VisibleItem> visibleItems(int level) {
    final labels = isGerman
        ? <String>[
            'Aktuelle oder kürzlich genutzte Linie',
            'Start- und Endzeit der Reise',
            'Zielbahnhof',
            'Halte, Linien und Umstiege',
            'Live-Fortschritt der Reise',
            'Genauer Standort während der Reise',
            'Letzter Standort für Routen zu dir',
            'Gespeicherte Favoriten mit Namen',
          ]
        : <String>[
            'Current or recently used transit line',
            'Journey start and end time',
            'Destination station',
            'Stops, lines, and transfers',
            'Live journey progress',
            'Exact location during a journey',
            'Latest location for routes to you',
            'Saved favorites with their labels',
          ];
    const icons = <IconData>[
      Icons.directions_transit,
      Icons.schedule,
      Icons.location_on_outlined,
      Icons.alt_route,
      Icons.timeline,
      Icons.my_location,
      Icons.route,
      Icons.star_outline,
    ];
    if (level == 0) return const [];
    return List.generate(
        level, (index) => _VisibleItem(icons[index], labels[index]));
  }

  _LevelDetails levelDetails(int level) {
    final english = <_LevelDetails>[
      const _LevelDetails(
        why:
            'A setting for the privacy concious who don’t want anyone to know what the’re up to.',
        privacyNote:
            'To you friends it might seem like you don’t even use the app. They can still chat with you and you can still choose to share your journey with them individually.',
      ),
      const _LevelDetails(
        why:
            'To show your transport line like a small status update without giving away too much. It should not be enough for someone to track you down easily.',
        privacyNote:
            'Only the transit line is shared. No schedule, destination, stops, or location is included.',
      ),
      const _LevelDetails(
        why:
            'For when you want your friends to know when you’ll depart and arrive without having to update them yourself each time.',
        privacyNote:
            'This adds the trip’s time window, but not its destination, stop list, or location. So your friends still need to know the meeting point if you’re meeting up.',
      ),
      const _LevelDetails(
        why:
            'Now your friends can make plans acordingly, knowing exactly when and where you’re supposed to arrive.',
        privacyNote:
            'Friends can see the destination station, but not the detailed itinerary or your live location.',
      ),
      const _LevelDetails(
        why:
            'Going one further your friends now know every stop you take along your journey, making meetups in between possible to continue your journey together.',
        privacyNote:
            'This reveals the planned transit itinerary, not live movement or an exact device location.',
      ),
      const _LevelDetails(
        why:
            'Now friends can see where your location aproximateley is based on the journey you’re taking.',
        privacyNote:
            'Progress is about the journey. Exact location sharing remains off until level 6.',
      ),
      const _LevelDetails(
        why:
            'Sometimes- a lot of the times, the estimated journey isn’t accurate enough. So if you feel comfortable sharing your actul device locatiion with your friends, you can use this level.',
        privacyNote:
            'Exact location is shared only while the app has detected a journey. It is not always-on sharing.',
      ),
      const _LevelDetails(
        why:
            'To let friends use you and your most recent tracked location as a destination, making it easier for them to get to you, no matter where you are.',
        privacyNote: 'Choose it only for people you trust.',
      ),
      const _LevelDetails(
        why:
            'Are you using your favorites to mark down cool places, like the best burgers in town? Or are you more a School, Work, Home type op Person? Whatever the case. Let your friends see all your saved favorites and navigate to them as they please.',
        privacyNote:
            'Favorites are shared in addition to everything in the levels below.',
      ),
    ];
    final german = <_LevelDetails>[
      const _LevelDetails(
        why:
            'Der vollständige Aus-Schalter fürs Teilen. Wähle ihn, wenn du für Freunde unsichtbar sein möchtest.',
        privacyNote:
            'Das Reisesignal löscht deine veröffentlichte Präsenz. Freunde sehen keine Linie, Reise oder Position.',
      ),
      const _LevelDetails(
        why:
            'Freunde sehen, dass du unterwegs bist, ohne Start oder Ziel deiner Reise zu erfahren.',
        privacyNote:
            'Es wird nur die Verkehrslinie geteilt. Fahrplan, Ziel, Halte und Standort bleiben privat.',
      ),
      const _LevelDetails(
        why:
            'Praktisch zum Abstimmen, etwa um ungefähr zu wissen, wann jemand unterwegs ist.',
        privacyNote:
            'Dazu kommt das Zeitfenster der Reise, nicht aber Ziel, Halte oder Standort.',
      ),
      const _LevelDetails(
        why:
            'Erleichtert das Treffen an einem Bahnhof, während die eigentliche Route privat bleibt.',
        privacyNote:
            'Freunde sehen den Zielbahnhof, aber weder den genauen Reiseverlauf noch deinen Live-Standort.',
      ),
      const _LevelDetails(
        why:
            'Für Menschen, die zusammen reisen und Halte, Linien und Umstiege vergleichen möchten.',
        privacyNote:
            'Der geplante Reiseverlauf wird geteilt – keine Live-Bewegung und kein genauer Gerätestandort.',
      ),
      const _LevelDetails(
        why:
            'Hilft Freunden, einer gemeinsamen Reise zu folgen und ihren Fortschritt zu sehen.',
        privacyNote:
            'Der Fortschritt bezieht sich auf die Reise. Der genaue Standort bleibt bis Stufe 6 aus.',
      ),
      const _LevelDetails(
        why:
            'Geeignet für enge Freunde, die sich während einer erkannten Reise finden möchten, etwa beim Umstieg.',
        privacyNote:
            'Der genaue Standort wird nur während einer erkannten Reise geteilt – nicht dauerhaft.',
      ),
      const _LevelDetails(
        why:
            'Ermöglicht Freunden eine Route zu dir, auch wenn gerade keine Reise erkannt wird.',
        privacyNote:
            'Dein letzter genauer Standort kann für Routen zu dir genutzt werden. Wähle das nur für vertraute Personen.',
      ),
      const _LevelDetails(
        why:
            'Vertraute Freunde können deine gespeicherten Orte nutzen, z. B. für eine Route zu deinem benannten Zuhause.',
        privacyNote:
            'Favoriten und ihre Bezeichnungen werden zusätzlich zu allen niedrigeren Stufen geteilt.',
      ),
    ];
    return (isGerman ? german : english)[level];
  }
}
