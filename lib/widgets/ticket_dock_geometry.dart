import 'package:flutter/widgets.dart';

/// Shared geometry of the ticket dock/undock flight.
///
/// The collapsed sheet's drag handle and the flight pill that stands in for it
/// have to sit on the exact same point for the whole gesture, or the pill
/// drifts off the card it belongs to. Both sides derive their positions from
/// here — including how far the sheet itself slides — so they cannot disagree.
@immutable
class TicketDockGeometry {
  const TicketDockGeometry._({required this.start, required this.end});

  /// Height of [Scaffold.bottomNavigationBar]'s content, safe area excluded.
  static const double navigationBarHeight = 72;

  /// Resting size of the ticket sheet, as a fraction of the body height.
  static const double collapsedSheetExtent = 0.1;

  /// 12px of list padding plus half of the 4px handle.
  static const double _handleCenterFromSheetTop = 14;

  /// 2px of item padding plus half of the 36px icon slot.
  static const double _navIconCenterFromNavTop = 20;

  /// Centre of the handle on the resting sheet.
  final Offset start;

  /// Centre of the QR icon in the navigation bar.
  final Offset end;

  factory TicketDockGeometry.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bodyHeight = size.height -
        navigationBarHeight -
        MediaQuery.paddingOf(context).bottom;
    return TicketDockGeometry._(
      start: Offset(
        size.width / 2,
        bodyHeight * (1 - collapsedSheetExtent) + _handleCenterFromSheetTop,
      ),
      end: Offset(
        size.width * 5 / 8,
        bodyHeight + _navIconCenterFromNavTop,
      ),
    );
  }

  /// Distance the handle — and therefore the sheet carrying it — covers over a
  /// full dock transition.
  Offset get travel => end - start;

  Offset lerp(double t) => Offset.lerp(start, end, t)!;
}
