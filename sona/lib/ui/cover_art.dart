import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/media_item.dart';

class CoverArt extends StatelessWidget {
  const CoverArt({super.key, required this.item, this.size = 64});
  final MediaItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = CustomPaint(
      painter: _CoverPainter(Color(item.color), item.art),
      child: size > 100
          ? Padding(
              padding: EdgeInsets.all(size * 0.09),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RAAGA',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: size * 0.035,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.title.toLowerCase(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: size * 0.12,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 100 ? 24 : 12),
      child: SizedBox.square(
        dimension: size,
        child: item.artworkUrl == null
            ? fallback
            : Image.network(
                item.artworkUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : fallback,
              ),
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.color, this.style);
  final Color color;
  final int style;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final paint = Paint()..color = const Color(0xCC17241D);
    canvas.save();
    canvas.translate(s * 0.65, s * 0.38);
    canvas.rotate(-0.35);
    if (style == 0) {
      for (var i = 0; i < 9; i++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: s * (0.78 - i * 0.065),
            height: s * (0.78 - i * 0.065),
          ),
          Paint()..color = Color.lerp(const Color(0xFF193126), color, i / 11)!,
        );
      }
    } else if (style == 1) {
      for (var i = 0; i < 8; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              -s * 0.52 + i * s * 0.09,
              -s * 0.35,
              s * 0.045,
              s * (0.35 + i * 0.06),
            ),
            Radius.circular(s * 0.025),
          ),
          paint,
        );
      }
    } else if (style == 2) {
      final path = Path();
      for (var i = 0; i < 12; i++) {
        final angle = i * math.pi / 6;
        final radius = i.isEven ? s * 0.45 : s * 0.17;
        final point = Offset(
          math.cos(angle) * radius,
          math.sin(angle) * radius,
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path..close(), paint);
      canvas.drawCircle(Offset.zero, s * 0.085, Paint()..color = color);
    } else {
      canvas.drawCircle(Offset(-s * 0.18, 0), s * 0.25, paint);
      canvas.drawCircle(
        Offset(s * 0.17, s * 0.09),
        s * 0.25,
        Paint()..color = const Color(0x9933453A),
      );
      for (var i = 0; i < 4; i++) {
        canvas.drawCircle(
          Offset(-s * 0.25 + i * s * 0.07, 0),
          s * 0.017,
          Paint()..color = color,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CoverPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.style != style;
}
