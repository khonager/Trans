import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/utils/app_error.dart';

import '../l10n/app_localizations.dart';

typedef StopDeparturesLoader = Future<List<Map<String, dynamic>>> Function(
  String stationId, {
  DateTime? date,
  int maxResults,
});

class StopDeparturesSheet extends StatefulWidget {
  final String stopId;
  final String stopName;
  final DateTime date;
  final String? preferredPlatform;
  final StopDeparturesLoader departuresLoader;

  const StopDeparturesSheet({
    super.key,
    required this.stopId,
    required this.stopName,
    required this.date,
    this.preferredPlatform,
    this.departuresLoader = TransportApi.fetchStopDepartures,
  });

  static Future<void> show(
    BuildContext context, {
    required String stopId,
    required String stopName,
    required DateTime date,
    String? preferredPlatform,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StopDeparturesSheet(
        stopId: stopId,
        stopName: stopName,
        date: date,
        preferredPlatform: preferredPlatform,
      ),
    );
  }

  @override
  State<StopDeparturesSheet> createState() => _StopDeparturesSheetState();
}

class _StopDeparturesSheetState extends State<StopDeparturesSheet> {
  static const int _fullDayMaxResults = 6000;

  late final Map<_ServiceDayType, DateTime> _sampleDates;
  late final Map<_ServiceDayType, _DayLoadState> _dayStates;
  _StopDeparturesData? _dataCache;
  String? _selectedDayTabId;
  String? _selectedPlatformKey;

  @override
  void initState() {
    super.initState();
    _sampleDates = _serviceDaySampleDates(widget.date);
    _dayStates = {
      for (final type in _ServiceDayType.values) type: const _DayLoadState(),
    };
    _selectedDayTabId = _serviceDayId(_serviceDayTypeForDate(widget.date));
    _loadInitialDay();
  }

  Future<void> _loadInitialDay() async {
    final initialType = _serviceDayTypeForDate(widget.date);
    await _ensureDayLoaded(initialType);
  }

  Future<void> _ensureDayLoaded(_ServiceDayType type) async {
    final state = _dayStates[type]!;
    if (state.isLoading || state.hasLoaded) return;

    setState(() {
      _dayStates[type] = state.copyWith(isLoading: true, error: null);
      _dataCache = null;
    });

    try {
      final departures = await _StopDeparturesProfiler.measureAsync(
        'stop_departures.load_day',
        context: 'stop=${widget.stopId} day=${_serviceDayId(type)}',
        action: () => widget.departuresLoader(
          widget.stopId,
          date: _sampleDates[type],
          maxResults: _fullDayMaxResults,
        ),
      );
      final sortedDepartures = _StopDeparturesProfiler.measureSync(
        'stop_departures.sort_day',
        context: '${_serviceDayId(type)} count=${departures.length}',
        action: () {
          final copy = List<Map<String, dynamic>>.from(departures);
          copy.sort(_departureSortCompare);
          return copy;
        },
      );

      if (!mounted) return;
      setState(() {
        _dayStates[type] = _DayLoadState(
          departures: sortedDepartures,
          hasLoaded: true,
        );
        _dataCache = null;
      });
      _syncSelectedPlatformKey();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dayStates[type] = _DayLoadState(
          isLoading: false,
          hasLoaded: true,
          error: error,
        );
        _dataCache = null;
      });
    }
  }

  _StopDeparturesData _currentData() {
    return _dataCache ??= _StopDeparturesData(
      dayTabs: _ServiceDayType.values
          .map(
            (type) => _DayTab(
              id: _serviceDayId(type),
              label: _serviceDayLabel(type),
              type: type,
              departures: _dayStates[type]!.departures,
            ),
          )
          .toList(),
    );
  }

  void _syncSelectedPlatformKey() {
    if (!mounted) return;
    final data = _currentData();
    final selectedDayTab =
        data.dayTabById(_selectedDayTabId) ?? data.defaultDayTab(widget.date);
    final platformTabs = data.platformTabsForDay(selectedDayTab.id);
    final nextPlatformKey = _resolvePlatformKey(
      platformTabs,
      currentKey: _selectedPlatformKey,
    );
    if (_selectedPlatformKey != nextPlatformKey) {
      setState(() {
        _selectedPlatformKey = nextPlatformKey;
      });
    }
  }

  String _serviceDayLabel(_ServiceDayType type) {
    return switch (type) {
      _ServiceDayType.weekday => 'Mo-Fr',
      _ServiceDayType.saturday => 'Sam',
      _ServiceDayType.sundayHoliday => 'So',
    };
  }

  String? _resolvePlatformKey(
    List<_PlatformTab> tabs, {
    String? currentKey,
  }) {
    if (tabs.isEmpty) return null;
    if (currentKey != null && tabs.any((tab) => tab.key == currentKey)) {
      return currentKey;
    }

    if (widget.preferredPlatform != null) {
      final platformMatch = tabs.cast<_PlatformTab?>().firstWhere(
            (tab) => tab?.platformLabel == widget.preferredPlatform,
            orElse: () => null,
          );
      if (platformMatch != null) return platformMatch.key;
    }

    final stopMatch = tabs.cast<_PlatformTab?>().firstWhere(
          (tab) => tab?.stopAreaId == widget.stopId,
          orElse: () => null,
        );
    if (stopMatch != null) return stopMatch.key;

    return tabs.first.key;
  }

  void _selectDayTab(String dayTabId, _StopDeparturesData data) {
    final platformTabs = data.platformTabsForDay(dayTabId);
    final type = _serviceDayTypeFromId(dayTabId);
    setState(() {
      _selectedDayTabId = dayTabId;
      _selectedPlatformKey = _resolvePlatformKey(
        platformTabs,
        currentKey: _selectedPlatformKey,
      );
    });
    if (type != null) {
      _ensureDayLoaded(type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final l10n = AppLocalizations.of(context)!;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.modalHandle.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.stopDeparturesTitle(widget.stopName),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Builder(
                  builder: (ctx) {
                    final data = _currentData();
                    final selectedDayTab = data.dayTabById(_selectedDayTabId) ??
                        data.defaultDayTab(widget.date);
                    final selectedDayState = _dayStates[selectedDayTab.type] ??
                        const _DayLoadState();
                    final platformTabs = data.platformTabsForDay(
                      selectedDayTab.id,
                    );
                    final selectedPlatformKey = _resolvePlatformKey(
                      platformTabs,
                      currentKey: _selectedPlatformKey,
                    );
                    final selectedPlatformTab =
                        platformTabs.cast<_PlatformTab?>().firstWhere(
                              (tab) => tab?.key == selectedPlatformKey,
                              orElse: () => null,
                            );
                    final departures = selectedPlatformTab?.departures ??
                        selectedDayTab.departures;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Row(
                            children: [
                              _FixedChipRow(
                                chips: data.dayTabs
                                    .map(
                                      (tab) => _ChipModel(
                                        label: tab.label,
                                        selected: tab.id == selectedDayTab.id,
                                        onTap: () =>
                                            _selectDayTab(tab.id, data),
                                      ),
                                    )
                                    .toList(),
                              ),
                              if (platformTabs.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _ChipBar(
                                    alignment: Alignment.centerRight,
                                    chips: platformTabs
                                        .map(
                                          (tab) => _ChipModel(
                                            label: tab.label,
                                            selected:
                                                tab.key == selectedPlatformKey,
                                            onTap: () => setState(
                                              () => _selectedPlatformKey =
                                                  tab.key,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          child: selectedDayState.isLoading &&
                                  selectedDayState.departures.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(),
                                      const SizedBox(height: 12),
                                      Text(
                                        l10n.loadingDepartures,
                                        style: TextStyle(
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : selectedDayState.error != null &&
                                      selectedDayState.departures.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          AppError.userMessage(
                                            context,
                                            selectedDayState.error!,
                                          ),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    )
                                  : departures.isEmpty
                                      ? Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Text(
                                              l10n.noDeparturesFound,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: colors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        )
                                      : _LazyLoopDeparturesList(
                                          key: ValueKey(
                                            '${selectedDayTab.id}|${selectedPlatformKey ?? 'all'}|${departures.length}',
                                          ),
                                          departures: departures,
                                          initialAnchorTime: widget.date,
                                          scrollController: scrollCtrl,
                                          colors: colors,
                                          l10n: l10n,
                                        ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChipBar extends StatelessWidget {
  final List<_ChipModel> chips;
  final Alignment alignment;

  const _ChipBar({
    required this.chips,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Align(
              alignment: alignment,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _FilterChip(
                      label: chips[i].label,
                      selected: chips[i].selected,
                      onTap: chips[i].onTap,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FixedChipRow extends StatelessWidget {
  final List<_ChipModel> chips;

  const _FixedChipRow({required this.chips});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _FilterChip(
              label: chips[i].label,
              selected: chips[i].selected,
              onTap: chips[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

enum _ServiceDayType { weekday, saturday, sundayHoliday }

String _serviceDayId(_ServiceDayType type) {
  return switch (type) {
    _ServiceDayType.weekday => 'mo_fr',
    _ServiceDayType.saturday => 'sam',
    _ServiceDayType.sundayHoliday => 'so',
  };
}

_ServiceDayType? _serviceDayTypeFromId(String id) {
  for (final type in _ServiceDayType.values) {
    if (_serviceDayId(type) == id) return type;
  }
  return null;
}

Map<_ServiceDayType, DateTime> _serviceDaySampleDates(DateTime anchor) {
  final normalizedAnchor = DateTime(anchor.year, anchor.month, anchor.day);
  final monday = normalizedAnchor.subtract(Duration(days: anchor.weekday - 1));
  final anchorType = _serviceDayTypeForDate(anchor);
  return <_ServiceDayType, DateTime>{
    _ServiceDayType.weekday:
        anchorType == _ServiceDayType.weekday ? normalizedAnchor : monday,
    _ServiceDayType.saturday: anchorType == _ServiceDayType.saturday
        ? normalizedAnchor
        : monday.add(const Duration(days: 5)),
    _ServiceDayType.sundayHoliday: anchorType == _ServiceDayType.sundayHoliday
        ? normalizedAnchor
        : monday.add(const Duration(days: 6)),
  };
}

_ServiceDayType _serviceDayTypeForDate(DateTime date) {
  return switch (date.weekday) {
    DateTime.saturday => _ServiceDayType.saturday,
    DateTime.sunday => _ServiceDayType.sundayHoliday,
    _ => _ServiceDayType.weekday,
  };
}

class _ChipModel {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChipModel({
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

class _DayLoadState {
  final bool isLoading;
  final bool hasLoaded;
  final List<Map<String, dynamic>> departures;
  final Object? error;

  const _DayLoadState({
    this.isLoading = false,
    this.hasLoaded = false,
    this.departures = const <Map<String, dynamic>>[],
    this.error,
  });

  _DayLoadState copyWith({
    bool? isLoading,
    bool? hasLoaded,
    List<Map<String, dynamic>>? departures,
    Object? error = _dayLoadStateNoChange,
  }) {
    return _DayLoadState(
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      departures: departures ?? this.departures,
      error: identical(error, _dayLoadStateNoChange) ? this.error : error,
    );
  }
}

const Object _dayLoadStateNoChange = Object();

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? colors.chipActiveBg : colors.chipBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? colors.chipActiveFg : colors.chipFg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  final Map<String, dynamic> dep;
  final TransColors colors;
  final AppLocalizations l10n;

  const _DepartureRow({
    required this.dep,
    required this.colors,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = _ParsedDeparture.fromMap(dep);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: parsed.isCancelled
                  ? Colors.red.withValues(alpha: 0.12)
                  : colors.chipBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              parsed.lineName.isNotEmpty ? parsed.lineName : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: parsed.isCancelled ? Colors.red : colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                decoration:
                    parsed.isCancelled ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parsed.direction.isNotEmpty ? parsed.direction : '—',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: parsed.isCancelled
                        ? colors.textSecondary
                        : colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration:
                        parsed.isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  parsed.metaLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 58),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  parsed.timeStr,
                  style: TextStyle(
                    color: parsed.isCancelled
                        ? colors.textSecondary
                        : (parsed.delayStr == null
                            ? colors.textPrimary
                            : parsed.timeColor),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    decoration:
                        parsed.isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (parsed.isCancelled)
                  Text(
                    l10n.cancelled,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                else if (parsed.delayStr != null)
                  Text(
                    parsed.delayStr!,
                    style: TextStyle(
                      color: parsed.timeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

class _LazyLoopDeparturesList extends StatefulWidget {
  final List<Map<String, dynamic>> departures;
  final DateTime initialAnchorTime;
  final ScrollController scrollController;
  final TransColors colors;
  final AppLocalizations l10n;

  const _LazyLoopDeparturesList({
    super.key,
    required this.departures,
    required this.initialAnchorTime,
    required this.scrollController,
    required this.colors,
    required this.l10n,
  });

  @override
  State<_LazyLoopDeparturesList> createState() =>
      _LazyLoopDeparturesListState();
}

class _LazyLoopDeparturesListState extends State<_LazyLoopDeparturesList> {
  static const int _windowChunk = 60;
  static const int _loadMarginPx = 320;
  static const double _rowExtentEstimate = 76;
  static const double _scrollDirectionThreshold = 3;
  static const Duration _loadIndicatorFrame = Duration(milliseconds: 16);

  int _anchorIndex = 0;
  int _visibleStart = 0;
  int _visibleEnd = -1;
  bool _didInitialJump = false;
  bool _isLoadingPrevious = false;
  bool _isLoadingNext = false;
  bool _showJumpToTop = false;
  bool _showJumpToBottom = false;
  double? _lastScrollPixels;
  int _jumpSuggestionDirection = 0;
  final GlobalKey _anchorRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _resetWindow();
    widget.scrollController.addListener(_updateJumpButtonVisibility);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_updateJumpButtonVisibility);
    super.dispose();
  }

  void _resetWindow() {
    final total = widget.departures.length;
    if (total == 0) {
      _anchorIndex = 0;
      _visibleStart = 0;
      _visibleEnd = -1;
      _didInitialJump = true;
      _isLoadingPrevious = false;
      _isLoadingNext = false;
      _showJumpToTop = false;
      _showJumpToBottom = false;
      _lastScrollPixels = null;
      _jumpSuggestionDirection = 0;
      return;
    }

    final referenceTime = _resolveAnchorReferenceTime(widget.initialAnchorTime);
    _anchorIndex = _indexForCurrentTime(
      widget.departures,
      referenceTime: referenceTime,
    );
    _visibleStart = (_anchorIndex - _windowChunk).clamp(0, total - 1);
    _visibleEnd = (_anchorIndex + _windowChunk).clamp(0, total - 1);
    _didInitialJump = false;
    _isLoadingPrevious = false;
    _isLoadingNext = false;
    _showJumpToTop = false;
    _showJumpToBottom = false;
    _lastScrollPixels = null;
    _jumpSuggestionDirection = 0;

    _StopDeparturesProfiler.log(
      'stop_departures.anchor',
      'reference=${referenceTime.toIso8601String()} index=$_anchorIndex '
          'visible=$_visibleStart-$_visibleEnd total=$total',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToAnchor();
      _updateJumpButtonVisibility();
    });
  }

  void _jumpToAnchor() {
    if (!mounted || _didInitialJump || !widget.scrollController.hasClients) {
      return;
    }
    final anchorContext = _anchorRowKey.currentContext;
    if (anchorContext != null) {
      _didInitialJump = true;
      Scrollable.ensureVisible(
        anchorContext,
        alignment: 0.28,
        duration: Duration.zero,
      );
      return;
    }

    final index = (_anchorIndex - _visibleStart).clamp(0, _visibleCount - 1);
    final fallbackTarget = (index * _rowExtentEstimate).toDouble();
    _didInitialJump = true;
    widget.scrollController.jumpTo(fallbackTarget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final retryContext = _anchorRowKey.currentContext;
      if (retryContext == null) return;
      Scrollable.ensureVisible(
        retryContext,
        alignment: 0.28,
        duration: Duration.zero,
      );
    });
  }

  int get _visibleCount {
    if (_visibleEnd < _visibleStart) return 0;
    return _visibleEnd - _visibleStart + 1;
  }

  bool _handleScroll(ScrollNotification notification) {
    if (widget.departures.isEmpty) return false;
    if (notification is! ScrollUpdateNotification &&
        notification is! OverscrollNotification &&
        notification is! ScrollEndNotification) {
      return false;
    }

    final metrics = notification.metrics;
    final nearTop = metrics.pixels <= _loadMarginPx;
    final nearBottom =
        metrics.pixels >= metrics.maxScrollExtent - _loadMarginPx;

    if (nearBottom) _scheduleLoadNextChunk();
    if (nearTop) _scheduleLoadPreviousChunk();

    return false;
  }

  void _updateJumpButtonVisibility() {
    if (!mounted || !widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final pixels = position.pixels;
    final previousPixels = _lastScrollPixels;
    _lastScrollPixels = pixels;

    final isScrollingDown = previousPixels != null &&
        pixels > previousPixels + _scrollDirectionThreshold;
    final isScrollingUp = previousPixels != null &&
        pixels < previousPixels - _scrollDirectionThreshold;
    if (isScrollingDown) {
      _jumpSuggestionDirection = 1;
    } else if (isScrollingUp) {
      _jumpSuggestionDirection = -1;
    }

    final atTop = pixels <= 1;
    final atBottom =
        position.maxScrollExtent > 0 && pixels >= position.maxScrollExtent - 1;
    final hasMoreAbove = _visibleStart > 0 || !atTop;
    final hasMoreBelow =
        _visibleEnd < widget.departures.length - 1 || !atBottom;
    final canJumpToBottom = _jumpSuggestionDirection > 0 && hasMoreBelow;
    final canJumpToTop = _jumpSuggestionDirection < 0 && hasMoreAbove;

    if (!canJumpToTop && !canJumpToBottom) {
      _jumpSuggestionDirection = 0;
    }

    if (_showJumpToTop == canJumpToTop &&
        _showJumpToBottom == canJumpToBottom) {
      return;
    }
    setState(() {
      _showJumpToTop = canJumpToTop;
      _showJumpToBottom = canJumpToBottom;
    });
  }

  Future<void> _scheduleLoadNextChunk() async {
    final total = widget.departures.length;
    if (_isLoadingNext || _visibleEnd >= total - 1) return;

    _StopDeparturesProfiler.log(
      'stop_departures.load_next_chunk.start',
      'visible=$_visibleStart-$_visibleEnd total=$total',
    );
    setState(() {
      _isLoadingNext = true;
    });
    await Future<void>.delayed(_loadIndicatorFrame);
    if (!mounted) return;

    setState(() {
      _visibleEnd = (_visibleEnd + _windowChunk).clamp(0, total - 1);
      _isLoadingNext = false;
    });
    _updateJumpButtonVisibility();
    _StopDeparturesProfiler.log(
      'stop_departures.load_next_chunk.done',
      'visible=$_visibleStart-$_visibleEnd total=$total',
    );
    _maybeEnableLoopMode();
  }

  Future<void> _scheduleLoadPreviousChunk() async {
    final total = widget.departures.length;
    if (_isLoadingPrevious || _visibleStart <= 0) return;

    final oldPixels = widget.scrollController.hasClients
        ? widget.scrollController.position.pixels
        : 0.0;
    final added = _visibleStart >= _windowChunk ? _windowChunk : _visibleStart;

    _StopDeparturesProfiler.log(
      'stop_departures.load_previous_chunk.start',
      'visible=$_visibleStart-$_visibleEnd total=$total',
    );
    setState(() {
      _isLoadingPrevious = true;
    });
    await Future<void>.delayed(_loadIndicatorFrame);
    if (!mounted) return;

    setState(() {
      _visibleStart = (_visibleStart - _windowChunk).clamp(0, total - 1);
      _isLoadingPrevious = false;
    });
    _StopDeparturesProfiler.log(
      'stop_departures.load_previous_chunk.done',
      'visible=$_visibleStart-$_visibleEnd total=$total',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      widget.scrollController.jumpTo(oldPixels + added * _rowExtentEstimate);
      _updateJumpButtonVisibility();
    });
    _maybeEnableLoopMode();
  }

  void _maybeEnableLoopMode() {
    // Intentionally disabled: switching into an artificial infinite scroll
    // range caused UI stalls on busy web runs right after lazy loading completed.
  }

  Future<void> _scrollToBoundary({required bool toEnd}) async {
    final total = widget.departures.length;
    if (total == 0 || !mounted) return;

    if (!_didInitialJump) {
      _jumpToAnchor();
    }

    final targetStart = toEnd ? (total - _windowChunk).clamp(0, total - 1) : 0;
    final targetEnd = toEnd ? total - 1 : _windowChunk.clamp(0, total - 1);

    setState(() {
      _visibleStart = targetStart;
      _visibleEnd = targetEnd;
      _isLoadingPrevious = false;
      _isLoadingNext = false;
      _jumpSuggestionDirection = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      widget.scrollController.jumpTo(
        toEnd ? widget.scrollController.position.maxScrollExtent : 0.0,
      );
      _updateJumpButtonVisibility();
      _StopDeparturesProfiler.log(
        toEnd
            ? 'stop_departures.jump_to_bottom'
            : 'stop_departures.jump_to_top',
        'visible=$_visibleStart-$_visibleEnd total=$total',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final departures = widget.departures;
    if (departures.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _handleScroll,
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 92),
            itemCount: _boundedItemCount,
            itemBuilder: (ctx, idx) {
              if (_isLoadingPrevious && idx == 0) {
                return _ChunkLoadingRow(
                  key: const ValueKey('stop_departures_loader_top'),
                  colors: widget.colors,
                  l10n: widget.l10n,
                );
              }

              final bottomLoaderIndex =
                  _boundedItemCount - (_isLoadingNext ? 1 : 0);
              if (_isLoadingNext && idx == bottomLoaderIndex) {
                return _ChunkLoadingRow(
                  key: const ValueKey('stop_departures_loader_bottom'),
                  colors: widget.colors,
                  l10n: widget.l10n,
                );
              }

              final effectiveIndex = idx - (_isLoadingPrevious ? 1 : 0);
              final realIdx = _visibleStart + effectiveIndex;
              final dep = departures[realIdx];
              return KeyedSubtree(
                key: realIdx == _anchorIndex ? _anchorRowKey : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DepartureRow(
                      dep: dep,
                      colors: widget.colors,
                      l10n: widget.l10n,
                    ),
                    Divider(
                      height: 1,
                      color: widget.colors.divider.withValues(alpha: 0.45),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_showJumpToBottom)
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _ScrollJumpTextButton(
                icon: Icons.keyboard_double_arrow_down,
                label: widget.l10n.stopDeparturesJumpToBottom,
                colors: widget.colors,
                onTap: () => _scrollToBoundary(toEnd: true),
              ),
            ),
          ),
        if (_showJumpToTop)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: _ScrollJumpTextButton(
                icon: Icons.keyboard_double_arrow_up,
                label: widget.l10n.stopDeparturesJumpToTop,
                colors: widget.colors,
                onTap: () => _scrollToBoundary(toEnd: false),
              ),
            ),
          ),
      ],
    );
  }

  int get _boundedItemCount {
    return _visibleCount +
        (_isLoadingPrevious ? 1 : 0) +
        (_isLoadingNext ? 1 : 0);
  }
}

class _ChunkLoadingRow extends StatelessWidget {
  final TransColors colors;
  final AppLocalizations l10n;

  const _ChunkLoadingRow({
    super.key,
    required this.colors,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              l10n.loadingDepartures,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollJumpTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final TransColors colors;
  final VoidCallback onTap;

  const _ScrollJumpTextButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.cardBg.withValues(alpha: 0.96),
      elevation: 4,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colors.textPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParsedDeparture {
  final String timeStr;
  final String? delayStr;
  final Color timeColor;
  final bool isCancelled;
  final String lineName;
  final String direction;
  final String metaLine;

  const _ParsedDeparture({
    required this.timeStr,
    required this.delayStr,
    required this.timeColor,
    required this.isCancelled,
    required this.lineName,
    required this.direction,
    required this.metaLine,
  });

  static final Expando<_ParsedDeparture> _cache =
      Expando<_ParsedDeparture>('parsed_departure');

  factory _ParsedDeparture.fromMap(Map<String, dynamic> dep) {
    final cached = _cache[dep];
    if (cached != null) return cached;

    String timeStr = '--:--';
    String? delayStr;
    Color timeColor = Colors.red;
    bool isCancelled = false;

    final motisDepObj = dep['departure'] as Map<String, dynamic>?;
    final motisPlaceObj = dep['place'] as Map<String, dynamic>?;
    if (motisDepObj != null || motisPlaceObj != null) {
      final scheduled = (motisDepObj?['scheduledTime'] as String?) ??
          (motisPlaceObj?['scheduledDeparture'] as String?) ??
          (motisPlaceObj?['scheduledArrival'] as String?);
      final actual = (motisDepObj?['time'] as String?) ??
          (motisPlaceObj?['departure'] as String?) ??
          (motisPlaceObj?['arrival'] as String?);
      final rawDelay = motisDepObj?['delay'];
      final delay = rawDelay is num
          ? rawDelay.toInt()
          : _calculateDelayMinutes(scheduled, actual);

      isCancelled = (dep['cancelled'] as bool?) ??
          (motisPlaceObj?['cancelled'] as bool?) ??
          false;

      final displayedTime = scheduled ?? actual;
      if (displayedTime != null) {
        final dt = DateTime.parse(displayedTime).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (delay != null && delay != 0) {
        final sign = delay > 0 ? '+' : '';
        delayStr = '$sign$delay\'';
        timeColor = delay > 2 ? Colors.red : Colors.green;
      }
    } else {
      final planned = dep['plannedWhen'] as String?;
      final actual = dep['when'] as String?;
      isCancelled = (dep['cancelled'] as bool?) ?? false;
      final displayedTime = planned ?? actual;
      if (displayedTime != null) {
        final dt = DateTime.parse(displayedTime).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      final delay = dep['delay'] as int?;
      if (delay != null && delay != 0) {
        final delayMin = (delay / 60).round();
        if (delayMin != 0) {
          final sign = delayMin > 0 ? '+' : '';
          delayStr = '$sign$delayMin\'';
          timeColor = delayMin > 2 ? Colors.red : Colors.green;
        }
      }
    }

    final routeShort = dep['routeShortName'] as String?;
    final headsign = dep['headsign'] as String?;
    final tripTo = dep['tripTo'] as Map<String, dynamic>?;
    final lineObj = dep['line'] as Map<String, dynamic>?;
    final platform = _platformLabel(dep);
    final stopLabel = _stopAreaName(dep);
    final metaParts = <String>[
      if (platform != null && platform.isNotEmpty) platform,
      if (stopLabel != null && stopLabel.isNotEmpty) stopLabel,
    ];

    final parsed = _ParsedDeparture(
      timeStr: timeStr,
      delayStr: delayStr,
      timeColor: timeColor,
      isCancelled: isCancelled,
      lineName: routeShort ??
          (dep['displayName'] as String?) ??
          (lineObj?['name'] as String?) ??
          '',
      direction: headsign ??
          (tripTo?['name'] as String?) ??
          (dep['direction'] as String?) ??
          '',
      metaLine: metaParts.isEmpty ? ' ' : metaParts.join(' • '),
    );
    _cache[dep] = parsed;
    return parsed;
  }
}

class _StopDeparturesData {
  final List<_DayTab> dayTabs;
  late final Map<String, List<_PlatformTab>> _platformTabsByDay =
      _StopDeparturesProfiler.measureSync(
    'stop_departures.build_platform_tabs_cache',
    context: 'days=${dayTabs.length}',
    action: () => {
      for (final tab in dayTabs) tab.id: _buildPlatformTabsForDay(tab),
    },
  );

  _StopDeparturesData({required this.dayTabs});

  _DayTab? dayTabById(String? id) {
    if (id == null) return null;
    return dayTabs.cast<_DayTab?>().firstWhere(
          (tab) => tab?.id == id,
          orElse: () => null,
        );
  }

  _DayTab defaultDayTab(DateTime date) {
    final serviceDayType = _serviceDayTypeForDate(date);
    return dayTabs.cast<_DayTab?>().firstWhere(
              (tab) => tab?.type == serviceDayType,
              orElse: () => dayTabs.isNotEmpty ? dayTabs.first : null,
            ) ??
        const _DayTab(
          id: 'empty',
          label: '',
          type: _ServiceDayType.weekday,
          departures: [],
        );
  }

  List<_PlatformTab> platformTabsForDay(String dayTabId) {
    return _platformTabsByDay[dayTabId] ?? const <_PlatformTab>[];
  }
}

List<_PlatformTab> _buildPlatformTabsForDay(_DayTab dayTab) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final dep in dayTab.departures) {
    final key = _platformKey(dep);
    grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(dep);
  }

  final groupedEntries = grouped.entries.toList();
  final duplicateCounts = <String, int>{};
  for (final entry in groupedEntries) {
    final label = _platformTabBaseLabel(entry.value.first);
    duplicateCounts[label] = (duplicateCounts[label] ?? 0) + 1;
  }
  final duplicateOrdinals = <String, int>{};

  final tabs = groupedEntries.map((entry) {
    final dep = entry.value.first;
    final baseLabel = _platformTabBaseLabel(dep);
    final duplicateCount = duplicateCounts[baseLabel] ?? 0;
    duplicateOrdinals[baseLabel] = (duplicateOrdinals[baseLabel] ?? 0) + 1;
    final label = duplicateCount > 1
        ? _platformTabDuplicateLabel(
            baseLabel,
            entry.value,
            ordinal: duplicateOrdinals[baseLabel]!,
          )
        : baseLabel;

    return _PlatformTab(
      key: entry.key,
      label: label.trim(),
      platformLabel: _platformLabel(dep),
      stopAreaId: _stopAreaId(dep),
      departures: entry.value,
    );
  }).toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  _StopDeparturesProfiler.log(
    'stop_departures.platform_tabs_built',
    'day=${dayTab.id} departures=${dayTab.departures.length} tabs=${tabs.length}',
  );
  return tabs;
}

String _platformTabBaseLabel(Map<String, dynamic> dep) {
  return _platformLabel(dep) ?? _stopAreaName(dep) ?? 'Stop';
}

String _platformTabDuplicateLabel(
  String baseLabel,
  List<Map<String, dynamic>> departures, {
  required int ordinal,
}) {
  final disambiguator = _platformTabDisambiguator(departures, ordinal: ordinal);
  return '$disambiguator · $baseLabel';
}

String _platformTabDisambiguator(
  List<Map<String, dynamic>> departures, {
  required int ordinal,
}) {
  final first = departures.first;
  final direction = _compactLabelPart(_shortDirection(first), maxLength: 18);
  if (direction.isNotEmpty) return direction;

  final lines = <String>[];
  for (final dep in departures) {
    final line = _lineName(dep);
    if (line == null || lines.contains(line)) continue;
    lines.add(line);
    if (lines.length == 2) break;
  }
  if (lines.isNotEmpty) {
    final suffix = departures.length > lines.length ? '+' : '';
    return _compactLabelPart('${lines.join(', ')}$suffix', maxLength: 18);
  }

  final stopId = _stopAreaId(first);
  if (stopId != null && stopId.isNotEmpty) {
    return '#${stopId.length > 5 ? stopId.substring(stopId.length - 5) : stopId}';
  }

  return ordinal.toString();
}

class _DayTab {
  final String id;
  final String label;
  final _ServiceDayType type;
  final List<Map<String, dynamic>> departures;

  const _DayTab({
    required this.id,
    required this.label,
    required this.type,
    required this.departures,
  });
}

class _PlatformTab {
  final String key;
  final String label;
  final String? platformLabel;
  final String? stopAreaId;
  final List<Map<String, dynamic>> departures;

  const _PlatformTab({
    required this.key,
    required this.label,
    required this.platformLabel,
    required this.stopAreaId,
    required this.departures,
  });
}

String _platformKey(Map<String, dynamic> dep) {
  final stopAreaId = _stopAreaId(dep) ?? '';
  final platformLabel = _platformLabel(dep) ?? '';
  return '$stopAreaId|$platformLabel';
}

String? _stopAreaId(Map<String, dynamic> dep) {
  final place = dep['place'] as Map<String, dynamic>?;
  final value = place?['stopId'] ?? place?['parentId'] ?? dep['stopId'];
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _stopAreaName(Map<String, dynamic> dep) {
  final place = dep['place'] as Map<String, dynamic>?;
  final text = (place?['description'] ?? place?['name'])?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _platformLabel(Map<String, dynamic> dep) {
  final place = dep['place'] as Map<String, dynamic>?;
  final platform = place?['track'] ??
      place?['scheduledTrack'] ??
      dep['platform'] ??
      dep['plannedPlatform'];
  final text = platform?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _direction(Map<String, dynamic> dep) {
  final tripTo = dep['tripTo'] as Map<String, dynamic>?;
  return (dep['headsign'] ?? tripTo?['name'] ?? dep['direction'] ?? '')
      .toString();
}

String? _lineName(Map<String, dynamic> dep) {
  final lineObj = dep['line'] as Map<String, dynamic>?;
  final text = (dep['routeShortName'] ?? dep['displayName'] ?? lineObj?['name'])
      ?.toString()
      .trim();
  return text == null || text.isEmpty ? null : text;
}

String _shortDirection(Map<String, dynamic> dep) {
  final direction = _direction(dep).trim();
  if (direction.isEmpty) return '';
  final words = direction.split(' ').where((part) => part.isNotEmpty).toList();
  return words.take(2).join(' ');
}

String _compactLabelPart(String label, {required int maxLength}) {
  final text = label.trim();
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength - 1).trimRight()}...';
}

int? _calculateDelayMinutes(String? scheduled, String? actual) {
  if (scheduled == null || actual == null) return null;
  try {
    return DateTime.parse(actual)
        .difference(DateTime.parse(scheduled))
        .inMinutes;
  } catch (_) {
    return null;
  }
}

DateTime? _departureDateTimeLocal(Map<String, dynamic> dep) {
  final cached = _departureDateTimeCache[dep];
  if (cached != null) {
    return identical(cached, _nullDateTimeSentinel) ? null : cached as DateTime;
  }
  final motisDepObj = dep['departure'] as Map<String, dynamic>?;
  final motisPlaceObj = dep['place'] as Map<String, dynamic>?;
  final rawTime = (motisDepObj?['scheduledTime'] as String?) ??
      (motisDepObj?['time'] as String?) ??
      (motisPlaceObj?['scheduledDeparture'] as String?) ??
      (motisPlaceObj?['departure'] as String?) ??
      (motisPlaceObj?['scheduledArrival'] as String?) ??
      (motisPlaceObj?['arrival'] as String?) ??
      (dep['plannedWhen'] as String?) ??
      (dep['when'] as String?);
  if (rawTime == null || rawTime.isEmpty) {
    _departureDateTimeCache[dep] = _nullDateTimeSentinel;
    return null;
  }
  try {
    final parsed = DateTime.parse(rawTime).toLocal();
    _departureDateTimeCache[dep] = parsed;
    return parsed;
  } catch (_) {
    _departureDateTimeCache[dep] = _nullDateTimeSentinel;
    return null;
  }
}

final Expando<Object> _departureDateTimeCache =
    Expando<Object>('departure_datetime');
final Object _nullDateTimeSentinel = Object();

int _departureSortCompare(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ta = _departureDateTimeLocal(a);
  final tb = _departureDateTimeLocal(b);
  if (ta == null && tb == null) return 0;
  if (ta == null) return 1;
  if (tb == null) return -1;
  return ta.compareTo(tb);
}

DateTime _resolveAnchorReferenceTime(DateTime initialAnchorTime) {
  final now = DateTime.now();
  final localAnchor = initialAnchorTime.toLocal();
  final isToday = localAnchor.year == now.year &&
      localAnchor.month == now.month &&
      localAnchor.day == now.day;
  return isToday ? now : localAnchor;
}

int _indexForCurrentTime(
  List<Map<String, dynamic>> departures, {
  required DateTime referenceTime,
}) {
  if (departures.isEmpty) return 0;

  final referenceMinutes = referenceTime.hour * 60 + referenceTime.minute;
  int? lastTimedIndex;
  for (var i = 0; i < departures.length; i++) {
    final time = _departureDateTimeLocal(departures[i]);
    if (time == null) continue;
    lastTimedIndex = i;
    final minutes = time.hour * 60 + time.minute;
    if (minutes >= referenceMinutes) return i;
  }
  return lastTimedIndex ?? 0;
}

class _StopDeparturesProfiler {
  static const Duration _warnThreshold = Duration(milliseconds: 8);

  static bool get _enabled => kDebugMode || kProfileMode;

  static void log(String label, String message) {
    if (!_enabled) return;
    debugPrint('[StopDepartures][$label] $message');
  }

  static T measureSync<T>(
    String label, {
    String? context,
    required T Function() action,
  }) {
    if (!_enabled) return action();

    final task = developer.TimelineTask()..start(label);
    final stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      stopwatch.stop();
      task.finish();
      if (stopwatch.elapsed >= _warnThreshold) {
        debugPrint(
          '[StopDepartures][$label] ${stopwatch.elapsedMilliseconds}ms'
          '${context == null ? '' : ' $context'}',
        );
      }
    }
  }

  static Future<T> measureAsync<T>(
    String label, {
    String? context,
    required Future<T> Function() action,
  }) async {
    if (!_enabled) return action();

    final task = developer.TimelineTask()..start(label);
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      task.finish();
      if (stopwatch.elapsed >= _warnThreshold) {
        debugPrint(
          '[StopDepartures][$label] ${stopwatch.elapsedMilliseconds}ms'
          '${context == null ? '' : ' $context'}',
        );
      }
    }
  }
}
