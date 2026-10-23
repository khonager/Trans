import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../data/tutorial_content.dart';

/// Opens above the entire app, including its navigation and ticket panel.
Future<void> showAppTutorial(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const TutorialScreen(),
    ),
  );
}

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  static const progressKey = 'tutorial_completed_lessons_v1';

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _search = TextEditingController();
  Set<String> _completed = {};
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _unfinishedOnly = false;

  bool get _german => Localizations.localeOf(context).languageCode == 'de';
  String _text(String en, String de) => _german ? de : en;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getStringList(TutorialScreen.progressKey) ?? [];
      if (!mounted) return;
      setState(() => _completed = completed.toSet());
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLesson(String id) async {
    if (_loading || _loadFailed || _saving) return;
    setState(() => _saving = true);
    final next = {..._completed};
    if (!next.add(id)) next.remove(id);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setStringList(
        TutorialScreen.progressKey,
        next.toList()..sort(),
      );
      if (!saved) throw StateError('Progress was not saved');
      if (mounted) setState(() => _completed = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_text(
          'Could not save progress. Please try again.',
          'Fortschritt konnte nicht gespeichert werden. Bitte erneut versuchen.',
        )),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final completedCount = tutorialLessons
        .where((lesson) => _completed.contains(lesson.id))
        .length;
    final allDone = completedCount == tutorialLessons.length;
    final query = _search.text.trim().toLowerCase();
    final visible = tutorialLessons.where((lesson) {
      final group = tutorialGroups.firstWhere((g) => g.id == lesson.group);
      return (!_unfinishedOnly || !_completed.contains(lesson.id)) &&
          '${group.title(_german)} ${lesson.copy(_german).join(' ')}'
              .toLowerCase()
              .contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: () => Navigator.of(context).pop()),
        title: Text(_text('Explore Trans', 'Trans entdecken')),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              key: const PageStorageKey('tutorial-list'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.effectiveSeed.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          allDone ? Icons.emoji_events : Icons.explore_outlined,
                          size: 36,
                          color: colors.effectiveSeed),
                      const SizedBox(height: 12),
                      Text(
                        allDone
                            ? _text('Trans explorer!', 'Trans-Profi!')
                            : _text('Your journey to knowing it all',
                                'Entdecke alles in deinem Tempo'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(_text(
                        'Open any lesson for instructions and a real-life use case. Mark it learned when you feel ready. Everything is optional, and you can revisit any lesson.',
                        'Öffne eine Lektion für eine Anleitung und ein Beispiel aus dem Alltag. Markiere sie als gelernt, wenn du bereit bist. Alles ist freiwillig und jederzeit erneut lesbar.',
                      )),
                      const SizedBox(height: 16),
                      if (_loading)
                        const LinearProgressIndicator()
                      else if (_loadFailed)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_text('Could not load your progress.',
                                'Fortschritt konnte nicht geladen werden.')),
                            TextButton.icon(
                              onPressed: _loadProgress,
                              icon: const Icon(Icons.refresh),
                              label: Text(_text('Retry', 'Erneut versuchen')),
                            ),
                          ],
                        )
                      else ...[
                        Text(
                          _text(
                            '$completedCount of ${tutorialLessons.length} learned',
                            '$completedCount von ${tutorialLessons.length} gelernt',
                          ),
                          key: const ValueKey('tutorial-progress'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: completedCount / tutorialLessons.length,
                          semanticsLabel: _text(
                              'Tutorial progress', 'Tutorial-Fortschritt'),
                          borderRadius: BorderRadius.circular(8),
                          minHeight: 8,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        _text(
                            'Progress is saved on this device. No account needed.',
                            'Fortschritt wird auf diesem Gerät gespeichert. Kein Konto nötig.'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _text('Search features', 'Funktionen suchen'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: _text('Clear search', 'Suche löschen'),
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(Icons.close),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilterChip(
                    label:
                        Text(_text('Unfinished only', 'Nur offene Lektionen')),
                    selected: _unfinishedOnly,
                    onSelected: (value) =>
                        setState(() => _unfinishedOnly = value),
                  ),
                ),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(query.isEmpty && allDone
                        ? _text(
                            'All explored! Turn off the filter to revisit lessons.',
                            'Alles entdeckt! Deaktiviere den Filter zum Nachlesen.')
                        : _text(
                            'No matching lessons. Try another search or filter.',
                            'Keine passenden Lektionen. Ändere die Suche oder den Filter.')),
                  ),
                for (final group in tutorialGroups)
                  if (visible.any((lesson) => lesson.group == group.id)) ...[
                    _groupHeader(group, colors),
                    for (final lesson
                        in visible.where((l) => l.group == group.id))
                      _lessonCard(lesson, colors),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupHeader(TutorialGroup group, TransColors colors) {
    final lessons = tutorialLessons.where((l) => l.group == group.id);
    final done = lessons.where((l) => _completed.contains(l.id)).length;
    final earned = !_loading && !_loadFailed && done == lessons.length;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Icon(earned ? Icons.verified_rounded : group.icon,
              color: colors.effectiveSeed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(group.title(_german),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(width: 8),
          Text(_loading || _loadFailed ? '—' : '$done / ${lessons.length}',
              semanticsLabel: earned
                  ? _text('Section completed', 'Abschnitt abgeschlossen')
                  : null),
        ],
      ),
    );
  }

  Widget _lessonCard(TutorialLesson lesson, TransColors colors) {
    final copy = lesson.copy(_german);
    final done = _completed.contains(lesson.id);
    return Card(
      color: colors.cardBg,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('tutorial-${lesson.id}'),
        leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? colors.effectiveSeed : colors.textSecondary),
        title: Text(copy[0]),
        subtitle: Text(done
            ? _text(
                'Learned · revisit anytime', 'Gelernt · jederzeit nachlesen')
            : _text('Tap to explore', 'Zum Entdecken antippen')),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(copy[1]),
          const SizedBox(height: 16),
          Text(_text('How to use it', 'So funktioniert es'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(copy[2]),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.effectiveSeed.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_text('Try it when…', 'Zum Beispiel…'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(copy[3]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: ValueKey('complete-${lesson.id}'),
            onPressed: _loading || _loadFailed || _saving
                ? null
                : () => _toggleLesson(lesson.id),
            icon: Icon(done ? Icons.undo : Icons.check),
            label: Text(done
                ? _text('Mark as unfinished', 'Als offen markieren')
                : _text('Got it · mark as learned',
                    'Verstanden · als gelernt markieren')),
          ),
        ],
      ),
    );
  }
}
