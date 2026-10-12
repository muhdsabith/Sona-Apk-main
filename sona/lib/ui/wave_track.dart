import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'olam_theme.dart';

class WaveTrack extends SliderTrackShape with BaseSliderTrackShape {
  const WaveTrack();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final canvas = context.canvas;
    final active = Paint()
      ..color = isEnabled ? accent : muted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final inactive = Paint()
      ..color = hairline
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rtl = textDirection == TextDirection.rtl;
    final start = rtl ? thumbCenter.dx : rect.left;
    final end = rtl ? rect.right : thumbCenter.dx;
    canvas.drawLine(
      Offset(rtl ? rect.left : thumbCenter.dx, rect.center.dy),
      Offset(rtl ? thumbCenter.dx : rect.right, rect.center.dy),
      inactive,
    );
    if (end <= start) return;
    final path = Path();
    for (double x = start; x <= end; x += 1) {
      final y =
          rect.center.dy +
          (isEnabled ? math.sin((x - thumbCenter.dx) * math.pi / 12) * 3 : 0);
      if (x == start)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(path, active);
  }
}
