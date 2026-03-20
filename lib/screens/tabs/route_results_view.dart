import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/utils/app_error.dart';
import 'package:trans/utils/format_utils.dart';
import 'package:trans/widgets/route_share_ticket.dart';
import '../../l10n/app_localizations.dart';

enum RouteSortOption {
  earliestDeparture,
  earliestArrival,
  shortestDuration,
  leastTransfers,
  shortestWait,
  leastWalking,
}

class RouteResultsView extends StatefulWidget {
  final List<Journey> candidates;
  final Function(Journey) onSelect;
  final VoidCallback onBack;
  final Future<void> Function()? onLoadEarlier;
  final Future<void> Function()? onLoadLater;
  final Future<void> Function()? onRefresh;
  final bool showTrainNumbers;

  const RouteResultsView({
    super.key,
    required this.candidates,
    required this.onSelect,
    required this.onBack,
    this.onLoadEarlier,
    this.onLoadLater,
    this.onRefresh,
    this.showTrainNumbers = false,
  });

  @override
  State<RouteResultsView> createState() => _RouteResultsViewState();
}

class _RouteResultsViewState extends State<RouteResultsView> {
  RouteSortOption _currentSort = RouteSortOption.earliestDeparture;
  late List<Journey> _sortedCandidates;
  bool _isLoadingMoreEarlier = false;
  bool _isLoadingMoreLater = false;

  // Ticket Generation
  final GlobalKey _ticketKey = GlobalKey();
  Journey? _ticketJourney;
  String _userName = "Anon";

  @override
  void initState() {
    super.initState();
    _sortCandidates();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final profile = await SupabaseService.getCurrentProfile();
    if (profile != null && profile['username'] != null) {
      if (mounted) {
        setState(() {
          _userName = profile['username'];
        });
      }
    } else {
      // Fallback to metadata if profile fetch fails but user exists
      final user = SupabaseService.currentUser;
      if (user != null && user.userMetadata?['username'] != null) {
        if (mounted) {
          setState(() {
            _userName = user.userMetadata!['username'];
          });
        }
      }
    }
  }

  @override
  void didUpdateWidget(RouteResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sortCandidates();
  }

  void _sortCandidates() {
    _sortedCandidates = List.from(widget.candidates);
    switch (_currentSort) {
      case RouteSortOption.earliestDeparture:
        _sortedCandidates.sort((a, b) => a.departure.compareTo(b.departure));
        break;
      case RouteSortOption.earliestArrival:
        _sortedCandidates.sort((a, b) => a.arrival.compareTo(b.arrival));
        break;
      case RouteSortOption.shortestDuration:
        _sortedCandidates.sort((a, b) => a.duration.compareTo(b.duration));
        break;
      case RouteSortOption.leastTransfers:
        _sortedCandidates
            .sort((a, b) => a.transferCount.compareTo(b.transferCount));
        break;
      case RouteSortOption.shortestWait:
        _sortedCandidates
            .sort((a, b) => a.totalWaitTime.compareTo(b.totalWaitTime));
        break;
      case RouteSortOption.leastWalking:
        _sortedCandidates.sort(
            (a, b) => a.totalWalkingDuration.compareTo(b.totalWalkingDuration));
        break;
    }
  }

  void _onSortChanged(RouteSortOption option) {
    setState(() {
      _currentSort = option;
      _sortCandidates();
    });
  }

  Future<void> _handleLoadEarlier() async {
    if (_isLoadingMoreEarlier) return;
    setState(() => _isLoadingMoreEarlier = true);
    await widget.onLoadEarlier?.call();
    if (mounted) setState(() => _isLoadingMoreEarlier = false);
  }

  Future<void> _handleLoadLater() async {
    if (_isLoadingMoreLater) return;
    setState(() => _isLoadingMoreLater = true);
    await widget.onLoadLater?.call();
    if (mounted) setState(() => _isLoadingMoreLater = false);
  }

  Future<void> _handleCopyJourney(Journey journey) async {
    setState(() => _ticketJourney = journey);

    // Ensure logo is loaded
    if (mounted) {
      await precacheImage(
          const AssetImage('lib/assets/logo_light.png'), context);
    }

    // Allow frame to build so RepaintBoundary can paint the new journey
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      final boundary = _ticketKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint("Boundary not found");
        return;
      }

      // Capture image
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final item = DataWriterItem();
        item.add(Formats.png(byteData.buffer.asUint8List()));
        await SystemClipboard.instance?.write([item]);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.routeTicketCopied),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e, st) {
      if (mounted) {
        AppError.showSnackBar(
          context,
          error: e,
          stackTrace: st,
          source: 'copy route ticket',
          fallback: AppLocalizations.of(context)!.serviceBusyPleaseTryAgain,
        );
      }
    } finally {
      if (mounted) setState(() => _ticketJourney = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return Stack(
      children: [
        Column(
          children: [
            // Header with Back button and Title
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: colors.textPrimary,
                    onPressed: widget.onBack,
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!
                          .routesFound(widget.candidates.length.toString()),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Sorting Options
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _SortChip(
                    label: AppLocalizations.of(context)!.earliestDep,
                    icon: Icons.schedule,
                    isSelected:
                        _currentSort == RouteSortOption.earliestDeparture,
                    onTap: () =>
                        _onSortChanged(RouteSortOption.earliestDeparture),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.earliestArr,
                    icon: Icons.timer_off,
                    isSelected: _currentSort == RouteSortOption.earliestArrival,
                    onTap: () =>
                        _onSortChanged(RouteSortOption.earliestArrival),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.fastest,
                    icon: Icons.flash_on,
                    isSelected:
                        _currentSort == RouteSortOption.shortestDuration,
                    onTap: () =>
                        _onSortChanged(RouteSortOption.shortestDuration),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.leastTransfers,
                    icon: Icons.directions_walk,
                    isSelected: _currentSort == RouteSortOption.leastTransfers,
                    onTap: () => _onSortChanged(RouteSortOption.leastTransfers),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.leastWait,
                    icon: Icons.hourglass_empty,
                    isSelected: _currentSort == RouteSortOption.shortestWait,
                    onTap: () => _onSortChanged(RouteSortOption.shortestWait),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.leastWalking,
                    icon: Icons.directions_walk,
                    isSelected: _currentSort == RouteSortOption.leastWalking,
                    onTap: () => _onSortChanged(RouteSortOption.leastWalking),
                  ),
                ],
              ),
            ),

            // List of Routes
            Expanded(
              child: RefreshIndicator(
                onRefresh: widget.onRefresh ?? () async {},
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      16, 16, 16, 100), // Extra bottom padding
                  // Items: "Load Earlier" button + routes + "Load Later" button
                  itemCount: _sortedCandidates.length + 2,
                  itemBuilder: (ctx, idx) {
                    if (idx == 0) {
                      // Load Earlier Button
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: _isLoadingMoreEarlier
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : _LoadTrigger(
                                  label:
                                      AppLocalizations.of(context)!.loadEarlier,
                                  icon: Icons.keyboard_arrow_up,
                                  onTap: _handleLoadEarlier,
                                ),
                        ),
                      );
                    }

                    if (idx == _sortedCandidates.length + 1) {
                      // Load Later Button
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: _isLoadingMoreLater
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : _LoadTrigger(
                                  label:
                                      AppLocalizations.of(context)!.loadLater,
                                  icon: Icons.keyboard_arrow_down,
                                  onTap: _handleLoadLater,
                                ),
                        ),
                      );
                    }

                    final journey = _sortedCandidates[idx - 1];
                    return _JourneyCard(
                      journey: journey,
                      onTap: () => widget.onSelect(journey),
                      onCopy: () => _handleCopyJourney(journey),
                      showTrainNumbers: widget.showTrainNumbers,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        // Hidden Ticket Widget for Generation
        Positioned(
          left: -2000,
          top: -2000,
          child: IgnorePointer(
            ignoring: true,
            child: ExcludeSemantics(
              child: UnconstrainedBox(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: _ticketKey,
                  child: _ticketJourney != null
                      ? RouteShareTicket(
                          journey: _ticketJourney!,
                          username: _userName,
                          showTrainNumbers: widget.showTrainNumbers,
                        )
                      : const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadTrigger extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _LoadTrigger({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.cardBg
              .withValues(alpha: 0.5), // Semi-transparent glass effect
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.navBarSelected : colors.chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : colors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final Journey journey;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final bool showTrainNumbers;

  const _JourneyCard({
    required this.journey,
    required this.onTap,
    required this.onCopy,
    this.showTrainNumbers = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final depStr = DateFormat('HH:mm').format(journey.departure);
    final arrStr = DateFormat('HH:mm').format(journey.arrival);
    final durStr = FormatUtils.formatDuration(journey.duration.inMinutes);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (journey.isCancelled) ...[
                          Text(
                            "$depStr - $arrStr",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              AppLocalizations.of(context)!.cancelled,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        ] else
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: depStr,
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary),
                                ),
                                if (journey.departureDelay != 0)
                                  TextSpan(
                                    text:
                                        " ${journey.departureDelay > 0 ? '+' : ''}${journey.departureDelay}",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: journey.departureDelay > 0
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                  ),
                                TextSpan(
                                  text: " - ",
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary),
                                ),
                                TextSpan(
                                  text: arrStr,
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary),
                                ),
                                if (journey.arrivalDelay != 0)
                                  TextSpan(
                                    text:
                                        " ${journey.arrivalDelay > 0 ? '+' : ''}${journey.arrivalDelay}",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: journey.arrivalDelay > 0
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      durStr,
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      AppLocalizations.of(context)!
                          .transfersCount(journey.transferCount.toString()),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Source badge
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: journey.source == 'motis'
                                ? Colors.blue.withValues(alpha: 0.2)
                                : Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(journey.source == 'motis' ? 'TRANS' : 'DB',
                            style: TextStyle(
                                color: journey.source == 'motis'
                                    ? Colors.blue
                                    : Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold))),
                    const SizedBox(height: 8),
                    // Copy Button
                    InkWell(
                      onTap: onCopy,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colors.cardBg.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Icon(Icons.copy,
                            size: 14, color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Line Summary (first 3 lines)
            Row(
              children: journey.steps
                  .where((s) => s.type == 'ride')
                  .take(4)
                  .map((step) {
                String displayLine = step.line.trim();
                // Clean train numbers if disabled
                if (!showTrainNumbers) {
                  final regexParens = RegExp(r'\s*\(\d+\)$');
                  displayLine = displayLine.replaceAll(regexParens, '').trim();
                  if (step.tripId != null) {
                    displayLine =
                        displayLine.replaceAll(step.tripId!, "").trim();
                  }
                } else {
                  // Ensure it's there if enabled
                  if (step.tripId != null &&
                      !displayLine.contains(step.tripId!)) {
                    displayLine += " (${step.tripId})";
                  }
                }

                return Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    displayLine,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
