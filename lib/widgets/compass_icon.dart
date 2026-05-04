import 'dart:math';

import 'package:flutter/material.dart';

class CompassIconPainter extends CustomPainter {
  final Color color;

  const CompassIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = 2;

    final center = Offset(size.width / 2, size.height / 2);
    final w = size.width;
    final h = size.height;

    canvas.drawCircle(center, 2.5, paint);
    _drawArrow(canvas, paint, Offset(2, h - 2), Offset(w / 2 - 3, h / 2 + 3));
    _drawArrow(canvas, paint, Offset(w - 2, 2), Offset(w / 2 + 3, h / 2 - 3));
  }

  void _drawArrow(Canvas canvas, Paint paint, Offset start, Offset end) {
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawLine(start, end, paint);

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final angle = atan2(dy, dx);
    const arrowSize = 6.0;
    final path = Path()
      ..moveTo(
        end.dx - arrowSize * cos(angle - pi / 6),
        end.dy - arrowSize * sin(angle - pi / 6),
      )
      ..lineTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowSize * cos(angle + pi / 6),
        end.dy - arrowSize * sin(angle + pi / 6),
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CompassIconPainter oldDelegate) =>
      color != oldDelegate.color;
}
