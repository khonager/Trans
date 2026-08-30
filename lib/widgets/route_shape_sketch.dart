import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/journey.dart';

/// One continuous piece of a journey's ground track, kept separate from its
/// neighbours so walking and riding can be drawn differently.
class RouteShapeSegment {
  final List<List<double>> points; // [[lat, lng], ...]
  final bool isWalk;

  const RouteShapeSegment({required this.points, required this.isWalk});
}

/// Parses one geometry point out of whatever the leg parsers stored in
/// [JourneyStep.path]; returns `null` when the entry is not a usable pair.
List<double>? _asLatLng(dynamic raw) {
  if (raw is! List || raw.length < 2) return null;
  final lat = raw[0];
  final lng = raw[1];
  if (lat is! num || lng is! num) return null;
  if (lat.isNaN || lng.isNaN) return null;
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  return [lat.toDouble(), lng.toDouble()];
}

/// Extracts the ground track of [journey] in travel order.
///
/// Uses the polylines that already ship with the plan response and falls back
/// to the straight line between a step's endpoints when a leg carries no
/// geometry, so a route always yields *some* shape.
List<RouteShapeSegment> routeShapeSegments(Journey journey) {
  final segments = <RouteShapeSegment>[];

  for (final step in journey.steps) {
    if (step.type == 'wait') continue;
    final isWalk = step.isWalking || step.type == 'walk' || step.type == 'bike';

    final points = <List<double>>[];
    for (final raw in step.path ?? const []) {
      final point = _asLatLng(raw);
      if (point == null) continue;
      // Collapse repeated coordinates; they only cost paint time.
      if (points.isNotEmpty &&
          points.last[0] == point[0] &&
          points.last[1] == point[1]) {
        continue;
      }
      points.add(point);
    }

    if (points.length < 2) {
      points.clear();
      final startLat = step.startLat;
      final startLng = step.startLng;
      final endLat = step.endLat;
      final endLng = step.endLng;
      if (startLat == null ||
          startLng == null ||
          endLat == null ||
          endLng == null) {
        continue;
      }
      points.add([startLat, startLng]);
      points.add([endLat, endLng]);
    }

    segments.add(RouteShapeSegment(points: points, isWalk: isWalk));
  }

  return segments;
}

/// Whether [segments] span enough ground to be worth drawing. A route whose
/// bounding box collapses to a point would only paint a smudge.
bool routeShapeIsRenderable(List<RouteShapeSegment> segments) {
  double? minLat, maxLat, minLng, maxLng;
  var count = 0;

  for (final segment in segments) {
    for (final point in segment.points) {
      count++;
      minLat = minLat == null ? point[0] : math.min(minLat, point[0]);
      maxLat = maxLat == null ? point[0] : math.max(maxLat, point[0]);
      minLng = minLng == null ? point[1] : math.min(minLng, point[1]);
      maxLng = maxLng == null ? point[1] : math.max(maxLng, point[1]);
    }
  }

  if (count < 2 ||
      minLat == null ||
      maxLat == null ||
      minLng == null ||
      maxLng == null) {
    return false;
  }
  // ~10 m; below that the "shape" is noise.
  return (maxLat - minLat) > 0.0001 || (maxLng - minLng) > 0.0001;
}

/// A thumbnail of the path a journey traces over the ground - no map, no
/// labels, just the line. Lets you tell a straight run from a detour or a loop
/// at a glance while scanning results.
class RouteShapeSketch extends StatelessWidget {
  final Journey journey;
  final Size size;

  const RouteShapeSketch({
    super.key,
    required this.journey,
    this.size = const Size(46, 32),
  });

  @override
  Widget build(BuildContext context) {
    final segments = routeShapeSegments(journey);
    if (!routeShapeIsRenderable(segments)) return const SizedBox.shrink();

    final colors = TransColors.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: size,
        painter: _RouteShapePainter(
          segments: segments,
          rideColor: colors.effectiveSeed,
          walkColor: colors.stepTransferText,
          endpointColor: colors.textSecondary,
        ),
      ),
    );
  }
}

class _RouteShapePainter extends CustomPainter {
  final List<RouteShapeSegment> segments;
  final Color rideColor;
  final Color walkColor;
  final Color endpointColor;

  const _RouteShapePainter({
    required this.segments,
    required this.rideColor,
    required this.walkColor,
    required this.endpointColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 3.0;
    final width = size.width - padding * 2;
    final height = size.height - padding * 2;
    if (width <= 0 || height <= 0) return;

    double? minLat, maxLat, minLng, maxLng;
    for (final segment in segments) {
      for (final point in segment.points) {
        minLat = minLat == null ? point[0] : math.min(minLat, point[0]);
        maxLat = maxLat == null ? point[0] : math.max(maxLat, point[0]);
        minLng = minLng == null ? point[1] : math.min(minLng, point[1]);
        maxLng = maxLng == null ? point[1] : math.max(maxLng, point[1]);
      }
    }
    if (minLat == null) return;

    // Equirectangular projection around the route's own latitude, so the
    // drawn shape keeps the proportions it has on a map instead of being
    // stretched east-west.
    final lngScale = math.cos((minLat + maxLat!) / 2 * math.pi / 180).abs();
    final spanX = math.max((maxLng! - minLng!) * lngScale, 1e-9);
    final spanY = math.max(maxLat - minLat, 1e-9);
    final scale = math.min(width / spanX, height / spanY);
    final offsetX = padding + (width - spanX * scale) / 2;
    final offsetY = padding + (height - spanY * scale) / 2;

    Offset project(List<double> point) => Offset(
          offsetX + (point[1] - minLng!) * lngScale * scale,
          // Flip: north belongs at the top.
          offsetY + (maxLat! - point[0]) * scale,
        );

    Offset? first;
    Offset? last;

    for (final segment in segments) {
      final path = Path();
      for (var i = 0; i < segment.points.length; i++) {
        final offset = project(segment.points[i]);
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
        first ??= offset;
        last = offset;
      }

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = segment.isWalk
            ? walkColor.withValues(alpha: 0.75)
            : rideColor.withValues(alpha: 0.9)
        ..strokeWidth = segment.isWalk ? 1.2 : 1.8;

      if (segment.isWalk) {
        _drawDashed(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }

    if (first == null || last == null) return;
    final dotPaint = Paint()..color = endpointColor.withValues(alpha: 0.7);
    canvas.drawCircle(first, 1.6, dotPaint);
    canvas.drawCircle(last, 1.6, dotPaint..color = rideColor);
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 2, metric.length)),
          paint,
        );
        distance += 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RouteShapePainter oldDelegate) =>
      !identical(oldDelegate.segments, segments) ||
      oldDelegate.rideColor != rideColor ||
      oldDelegate.walkColor != walkColor ||
      oldDelegate.endpointColor != endpointColor;
}
