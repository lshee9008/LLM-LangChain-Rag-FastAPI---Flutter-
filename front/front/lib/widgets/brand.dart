import 'package:flutter/material.dart';

import '../theme/blues_theme.dart';

class BluesBrand extends StatelessWidget {
  final bool light;
  final bool compact;
  const BluesBrand({super.key, this.light = false, this.compact = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: light ? Colors.white.withValues(alpha: .1) : BluesColors.blue,
          borderRadius: BorderRadius.circular(12),
          border: light ? Border.all(color: Colors.white24) : null,
        ),
        child: const Icon(Icons.sports_soccer, color: Colors.white, size: 23),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BLUES BOT',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: light ? Colors.white : BluesColors.ink,
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            if (!compact)
              Text(
                'YOUR CHELSEA COMPANION',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.35,
                  color: light ? const Color(0xFFB7C6E5) : BluesColors.muted,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// A decorative pitch, rather than an official club crest or live match graphic.
class PitchArt extends StatelessWidget {
  final Color color;
  const PitchArt({super.key, this.color = Colors.white});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _PitchPainter(color),
      size: const Size(240, 300),
    ),
  );
}

class _PitchPainter extends CustomPainter {
  final Color color;
  _PitchPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rect = Rect.fromLTWH(
      size.width * .12,
      size.height * .08,
      size.width * .76,
      size.height * .84,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      p,
    );
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      p,
    );
    canvas.drawCircle(rect.center, rect.width * .19, p);
    canvas.drawCircle(rect.center, 2, p..style = PaintingStyle.fill);
    p.style = PaintingStyle.stroke;
    for (final top in [true, false]) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + rect.width * .23,
          top ? rect.top : rect.bottom - rect.height * .17,
          rect.width * .54,
          rect.height * .17,
        ),
        p,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + rect.width * .36,
          top ? rect.top : rect.bottom - rect.height * .065,
          rect.width * .28,
          rect.height * .065,
        ),
        p,
      );
    }
    final dot = Paint()..color = color.withValues(alpha: .85);
    for (final o in [
      const Offset(.34, .67),
      const Offset(.66, .58),
      const Offset(.48, .32),
    ]) {
      canvas.drawCircle(Offset(size.width * o.dx, size.height * o.dy), 5, dot);
    }
    canvas.drawLine(
      Offset(size.width * .34, size.height * .67),
      Offset(size.width * .66, size.height * .58),
      p,
    );
    canvas.drawLine(
      Offset(size.width * .66, size.height * .58),
      Offset(size.width * .48, size.height * .32),
      p,
    );
  }

  @override
  bool shouldRepaint(_PitchPainter oldDelegate) => color != oldDelegate.color;
}
