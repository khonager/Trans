import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// Draws a light that travels along the outline of [child].
///
/// The line sits exactly on the edge of the shape - no outer glow, no halo -
/// and is used to point at a control that has something new to offer without
/// stealing attention the way a colour fill would.
class RunningBorder extends StatefulWidget {
  const RunningBorder({
    super.key,
    required this.child,
    required this.color,
    this.active = true,
    this.borderRadius = 20,
    this.strokeWidth = 1.6,
    this.period = const Duration(milliseconds: 4400),
    this.trailFraction = 0.5,
  });

  final Widget child;
  final Color color;
  final bool active;
  final double borderRadius;
  final double strokeWidth;

  /// Time for one full lap around the outline.
  final Duration period;

  /// Share of the outline covered by the fading tail behind the head.
  final double trailFraction;

  @override
  State<RunningBorder> createState() => _RunningBorderState();
}

class _RunningBorderState extends State<RunningBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy controller would first come to life in dispose(),
    // where its ticker can no longer reach the widget tree.
    _controller = AnimationController(vsync: this, duration: widget.period);
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(RunningBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) {
      _controller.duration = widget.period;
    }
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;

    // Honour the system "reduce motion" setting: the hint stays, it just does
    // not move.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return CustomPaint(
        foregroundPainter: _RunningBorderPainter(
          progress: 0,
          color: widget.color,
          borderRadius: widget.borderRadius,
          strokeWidth: widget.strokeWidth,
          trailFraction: widget.trailFraction,
          still: true,
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        foregroundPainter: _RunningBorderPainter(
          progress: _controller.value,
          color: widget.color,
          borderRadius: widget.borderRadius,
          strokeWidth: widget.strokeWidth,
          trailFraction: widget.trailFraction,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _RunningBorderPainter extends CustomPainter {
  _RunningBorderPainter({
    required this.progress,
    required this.color,
    required this.borderRadius,
    required this.strokeWidth,
    required this.trailFraction,
    this.still = false,
  });

  final double progress;
  final Color color;
  final double borderRadius;
  final double strokeWidth;
  final double trailFraction;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Inset by half the stroke so the line lands on the edge instead of
    // straddling it.
    final inset = strokeWidth / 2;
    final bounds = (Offset.zero & size).deflate(inset);
    if (bounds.width <= 0 || bounds.height <= 0) return;

    final radius = math.min(
      borderRadius,
      math.min(bounds.width, bounds.height) / 2,
    );
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(bounds, Radius.circular(radius)));

    final metrics = outline.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final length = metric.length;
    if (length <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (still) {
      paint.color = color.withValues(alpha: 0.45);
      canvas.drawPath(outline, paint);
      return;
    }

    final trail = length * trailFraction.clamp(0.05, 0.95);
    final head = progress * length;
    final trailPath = _extractTrail(metric, length, head - trail, head);

    // One stroked path with a sweep shader, so the tail fades continuously
    // instead of breaking into segments.
    paint.shader = _trailShader(metric, bounds, length, head, trail);
    canvas.drawPath(trailPath, paint);
  }

  /// The slice of the outline between [from] and [to], wrapping at the seam.
  Path _extractTrail(
    PathMetric metric,
    double length,
    double from,
    double to,
  ) {
    var start = from % length;
    var end = to % length;
    if (start < 0) start += length;
    if (end < 0) end += length;

    if (end >= start) return metric.extractPath(start, end);
    return Path()
      ..addPath(metric.extractPath(start, length), Offset.zero)
      ..addPath(metric.extractPath(0, end), Offset.zero);
  }

  /// A sweep gradient that runs from transparent at the tail to full colour at
  /// the head. The outline is convex, so the angle around its centre grows
  /// monotonically along the path and the fade never doubles back.
  ///
  /// The stops cover the whole circle even though only the trail is stroked:
  /// a gradient that ended at the head would clamp everything behind the tail
  /// to full colour, and the round cap there would show up as a bright dot.
  Shader _trailShader(
    PathMetric metric,
    Rect bounds,
    double length,
    double head,
    double trail,
  ) {
    final center = bounds.center;
    final headTangent = metric.getTangentForOffset(head % length);
    final tailTangent = metric.getTangentForOffset((head - trail) % length);
    final transparent = color.withValues(alpha: 0);

    if (headTangent == null || tailTangent == null) {
      return SweepGradient(colors: [color, color]).createShader(bounds);
    }

    final headAngle = _angleFrom(center, headTangent.position);
    final tailAngle = _angleFrom(center, tailTangent.position);

    // Which way the angle turns as the head advances.
    final radius = headTangent.position - center;
    final heading = headTangent.vector;
    final turnsForward = radius.dx * heading.dy - radius.dy * heading.dx >= 0;

    final span = math.max(
      _positiveSpan(
          turnsForward ? headAngle - tailAngle : tailAngle - headAngle),
      0.05,
    );
    // Share of the full circle the trail occupies.
    final reach = (span / (2 * math.pi)).clamp(0.02, 0.9);
    // A little slack past the head so its round cap stays lit.
    final capSlack = math.min(reach + 0.015, 0.99);

    return SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: turnsForward
          ? [transparent, color.withValues(alpha: 0.12), color, transparent]
          : [color, color.withValues(alpha: 0.12), transparent, transparent],
      stops: turnsForward
          ? [0, reach * 0.6, capSlack, math.min(capSlack + 0.015, 1.0)]
          : [0, reach * 0.4, reach, 1.0],
      transform: GradientRotation(turnsForward ? tailAngle : headAngle),
    ).createShader(bounds);
  }

  double _angleFrom(Offset center, Offset point) =>
      math.atan2(point.dy - center.dy, point.dx - center.dx);

  double _positiveSpan(double angle) {
    var span = angle;
    while (span <= 0) {
      span += 2 * math.pi;
    }
    return span;
  }

  @override
  bool shouldRepaint(_RunningBorderPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.trailFraction != trailFraction ||
      oldDelegate.still != still;
}
