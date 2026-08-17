import 'dart:math';
import 'package:flutter/material.dart';
import '../database/database_manager.dart';

class ProgressPoint {
  final DateTime date;
  final double percent;
  const ProgressPoint(this.date, this.percent);
}

class ProgressGraphData {
  static Future<List<ProgressPoint>> load() async {
    final db = await DatabaseManager.db;
    final totalRows = await db.rawQuery(
        'SELECT COALESCE(SUM(frequency),0) AS total FROM vocab_words WHERE frequency > 0');
    final totalOccurrences = (totalRows.first['total'] as int?) ?? 77430;
    if (totalOccurrences == 0) return [];

    final rows = await db.rawQuery('''
      SELECT k.marked_at, v.frequency
      FROM known_words k
      JOIN vocab_words v ON v.id = k.vocab_word_id
      WHERE k.marked_at IS NOT NULL AND v.frequency > 0
      ORDER BY k.marked_at ASC
    ''');
    if (rows.isEmpty) return [];

    final Map<String, int> dayFreq = {};
    for (final r in rows) {
      final ms = r['marked_at'] as int? ?? 0;
      final freq = r['frequency'] as int? ?? 0;
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dayFreq[key] = (dayFreq[key] ?? 0) + freq;
    }

    final sortedKeys = dayFreq.keys.toList()..sort();
    final points = <ProgressPoint>[];
    int cumulative = 0;
    final firstDate = DateTime.parse(sortedKeys.first);
    points.add(ProgressPoint(firstDate.subtract(const Duration(days: 1)), 0.0));
    for (final key in sortedKeys) {
      cumulative += dayFreq[key]!;
      final pct = (cumulative / totalOccurrences * 100).clamp(0.0, 100.0);
      points.add(ProgressPoint(DateTime.parse(key), pct));
    }
    return points;
  }
}

class ProgressGraph extends StatefulWidget {
  final List<ProgressPoint> points;
  final bool isDark;
  const ProgressGraph({super.key, required this.points, required this.isDark});

  @override
  State<ProgressGraph> createState() => _ProgressGraphState();
}

class _ProgressGraphState extends State<ProgressGraph>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        painter: _GraphPainter(
          points: widget.points,
          progress: _anim.value,
          isDark: widget.isDark,
        ),
        child: const SizedBox(width: double.infinity, height: 220),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<ProgressPoint> points;
  final double progress;
  final bool isDark;

  static const _green = Color(0xFF1B4332);
  static const _gold  = Color(0xFFD4AF37);
  static const _teal  = Color(0xFF2D6A4F);

  // Adaptive colors based on theme
  Color get _axisColor    => isDark ? Colors.white70    : Colors.black54;
  Color get _gridColor    => isDark ? Colors.white12    : Colors.black.withValues(alpha: 0.08);
  Color get _labelColor   => isDark ? Colors.white60    : Colors.black54;
  Color get _captionColor => isDark ? Colors.white38    : Colors.black38;
  Color get _bgPill       => isDark ? const Color(0xFF0D1B12) : Colors.white;

  static const padL = 52.0;
  static const padR = 20.0;
  static const padT = 30.0;
  static const padB = 48.0;

  _GraphPainter({
    required this.points,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final gW = size.width - padL - padR;
    final gH = size.height - padT - padB;

    final minDate = points.first.date.millisecondsSinceEpoch.toDouble();
    final maxDate = points.last.date.millisecondsSinceEpoch.toDouble();
    final dateRange = (maxDate - minDate).abs();

    Offset toXY(ProgressPoint p) {
      final x = padL +
          (dateRange == 0
              ? 0
              : (p.date.millisecondsSinceEpoch - minDate) / dateRange * gW);
      final y = padT + gH - (p.percent / 100.0 * gH);
      return Offset(x, y);
    }

    // ── Y grid lines + labels ────────────────────────────────────────────
    for (int i = 0; i <= 4; i++) {
      final pct = i * 25.0;
      final y = padT + gH - (pct / 100.0 * gH);

      // Grid line
      canvas.drawLine(
        Offset(padL, y),
        Offset(size.width - padR, y),
        Paint()
          ..color = _gridColor
          ..strokeWidth = 1.0,
      );

      // Tick
      canvas.drawLine(
        Offset(padL - 5, y),
        Offset(padL, y),
        Paint()
          ..color = _axisColor
          ..strokeWidth = 1.2,
      );

      // Label
      _drawText(canvas, '${pct.toInt()}%',
          Offset(padL - 8, y - 6),
          fontSize: 9.5,
          color: _labelColor,
          alignRight: true);
    }

    // Y axis caption (rotated)
    _drawRotatedText(canvas, '↑ Coverage', size, gH);

    // ── X axis date labels ───────────────────────────────────────────────
    final labelCount = min(5, points.length);
    for (int i = 0; i < labelCount; i++) {
      final idx =
          ((i / (labelCount - 1)) * (points.length - 1)).round()
          .clamp(0, points.length - 1);
      final pt = points[idx];
      final x = toXY(pt).dx;
      final baseY = padT + gH;

      // Tick
      canvas.drawLine(
        Offset(x, baseY),
        Offset(x, baseY + 4),
        Paint()
          ..color = _axisColor
          ..strokeWidth = 1.2,
      );

      // Date label
      _drawText(
        canvas,
        '${pt.date.day} ${_monthAbbr(pt.date.month)}',
        Offset(x, baseY + 7),
        fontSize: 9,
        color: _labelColor,
        center: true,
      );
    }

    // X axis caption
    _drawText(
      canvas,
      'Date →',
      Offset(padL + gW / 2, size.height - 8),
      fontSize: 9.5,
      color: _captionColor,
      center: true,
    );

    // ── Axes ─────────────────────────────────────────────────────────────
    final axisPaint = Paint()
      ..color = _axisColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Y axis
    canvas.drawLine(
        Offset(padL, padT - 6), Offset(padL, padT + gH), axisPaint);
    // X axis
    canvas.drawLine(
        Offset(padL, padT + gH),
        Offset(size.width - padR, padT + gH),
        axisPaint);

    // Y arrow
    final yArr = Path()
      ..moveTo(padL - 4, padT - 2)
      ..lineTo(padL, padT - 8)
      ..lineTo(padL + 4, padT - 2);
    canvas.drawPath(yArr, axisPaint);

    // X arrow
    final xArr = Path()
      ..moveTo(size.width - padR - 2, padT + gH - 4)
      ..lineTo(size.width - padR + 4, padT + gH)
      ..lineTo(size.width - padR - 2, padT + gH + 4);
    canvas.drawPath(xArr, axisPaint);

    // ── Animated curve ────────────────────────────────────────────────────
    final totalSeg = points.length - 1;
    final progSeg  = progress * totalSeg;
    final fullSeg  = progSeg.floor();
    final partial  = progSeg - fullSeg;

    final drawn = <Offset>[];
    for (int i = 0; i <= min(fullSeg, totalSeg); i++) {
      drawn.add(toXY(points[i]));
    }

    Offset? tip;
    if (fullSeg < totalSeg && drawn.isNotEmpty) {
      final from = drawn.last;
      final to   = toXY(points[fullSeg + 1]);
      tip = Offset(
        from.dx + (to.dx - from.dx) * partial,
        from.dy + (to.dy - from.dy) * partial,
      );
      drawn.add(tip);
    } else if (drawn.isNotEmpty) {
      tip = drawn.last;
    }

    // Gradient fill
    if (drawn.length >= 2) {
      final fp = Path()..moveTo(drawn.first.dx, padT + gH);
      for (final pt in drawn) fp.lineTo(pt.dx, pt.dy);
      fp
        ..lineTo(drawn.last.dx, padT + gH)
        ..close();
      canvas.drawPath(
        fp,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _teal.withValues(alpha: 0.45),
              _teal.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(padL, padT, gW, gH)),
      );
    }

    // Curve line
    if (drawn.length >= 2) {
      final lp = Path()..moveTo(drawn.first.dx, drawn.first.dy);
      for (int i = 1; i < drawn.length; i++) {
        final prev = drawn[i - 1];
        final curr = drawn[i];
        final cpX  = (prev.dx + curr.dx) / 2;
        lp.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
      }
      canvas.drawPath(
        lp,
        Paint()
          ..color = _teal
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Vertical dashed line from tip to X axis
    if (tip != null) {
      final dp = Paint()
        ..color = _gold.withValues(alpha: 0.5)
        ..strokeWidth = 1.0;
      double dy = tip.dy + 6;
      while (dy < padT + gH) {
        canvas.drawLine(
          Offset(tip.dx, dy),
          Offset(tip.dx, min(dy + 4, padT + gH)),
          dp,
        );
        dy += 8;
      }
    }

    // Animated dot
    if (tip != null) {
      canvas.drawCircle(tip, 11, Paint()..color = _gold.withValues(alpha: 0.18));
      canvas.drawCircle(tip, 7,  Paint()..color = _gold.withValues(alpha: 0.55));
      canvas.drawCircle(tip, 4,  Paint()..color = _gold);

      // Live pct
      double currentPct = 0;
      if (fullSeg < points.length) {
        final fromPct = points[fullSeg].percent;
        final toPct   = fullSeg + 1 < points.length
            ? points[fullSeg + 1].percent
            : fromPct;
        currentPct = fromPct + (toPct - fromPct) * partial;
      } else {
        currentPct = points.last.percent;
      }

      final label = '${currentPct.toStringAsFixed(1)}%';
      final tp    = _makeTP(label, fontSize: 11, color: _gold, bold: true);
      final lx    = (tip.dx - tp.width / 2)
          .clamp(padL, size.width - padR - tp.width);
      final ly    = tip.dy - 24;

      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(lx - 6, ly - 2, tp.width + 12, tp.height + 4),
        const Radius.circular(6),
      );
      canvas.drawRRect(rr,
          Paint()..color = _bgPill.withValues(alpha: 0.92));
      canvas.drawRRect(
        rr,
        Paint()
          ..color = _gold.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      tp.paint(canvas, Offset(lx, ly));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  TextPainter _makeTP(String text,
      {double fontSize = 10,
      Color? color,
      bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color ?? _labelColor,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  void _drawText(Canvas canvas, String text, Offset offset,
      {double fontSize = 10,
      Color? color,
      bool alignRight = false,
      bool center = false,
      bool bold = false}) {
    final tp = _makeTP(text,
        fontSize: fontSize, color: color ?? _labelColor, bold: bold);
    double dx = offset.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, offset.dy));
  }

  void _drawRotatedText(
      Canvas canvas, String text, Size size, double gH) {
    final tp = _makeTP(text, fontSize: 9.5, color: _captionColor);
    canvas.save();
    final cx = padL - 38.0;
    final cy = padT + gH / 2;
    canvas.translate(cx, cy);
    canvas.rotate(-3.14159 / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  String _monthAbbr(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.progress != progress || old.isDark != isDark;
}