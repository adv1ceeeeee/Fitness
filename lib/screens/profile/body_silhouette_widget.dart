import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';

// ─── Measurement data class ───────────────────────────────────────────────────

class _Measures {
  final double shoulder;
  final double chest;
  final double waist;
  final double hips;
  final double thigh;
  final double calf;

  const _Measures({
    required this.shoulder,
    required this.chest,
    required this.waist,
    required this.hips,
    required this.thigh,
    required this.calf,
  });

  static const defaults = _Measures(
    shoulder: 114.0,
    chest: 97.0,
    waist: 84.0,
    hips: 96.0,
    thigh: 57.0,
    calf: 37.0,
  );

  static _Measures fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    double use(String key, double def) =>
        m[key] != null ? (m[key] as num).toDouble() : def;
    double avg(String a, String b, double def) {
      final va = (m[a] as num?)?.toDouble();
      final vb = (m[b] as num?)?.toDouble();
      if (va != null && vb != null) return (va + vb) / 2;
      return va ?? vb ?? def;
    }

    return _Measures(
      shoulder: use('shoulders_cm', defaults.shoulder),
      chest:    use('chest_cm',     defaults.chest),
      waist:    use('waist_cm',     defaults.waist),
      hips:     use('hips_cm',      defaults.hips),
      thigh:    avg('left_thigh_cm', 'right_thigh_cm', defaults.thigh),
      calf:     avg('left_calf_cm',  'right_calf_cm',  defaults.calf),
    );
  }

  _Measures lerp(_Measures other, double t) => _Measures(
        shoulder: _lv(shoulder, other.shoulder, t),
        chest:    _lv(chest,    other.chest,    t),
        waist:    _lv(waist,    other.waist,    t),
        hips:     _lv(hips,     other.hips,     t),
        thigh:    _lv(thigh,    other.thigh,    t),
        calf:     _lv(calf,     other.calf,     t),
      );

  static double _lv(double a, double b, double t) => a + (b - a) * t;
}

// ─── Public widget ────────────────────────────────────────────────────────────

class BodySilhouetteWidget extends StatefulWidget {
  final Map<String, dynamic>? measurements;

  const BodySilhouetteWidget({super.key, this.measurements});

  @override
  State<BodySilhouetteWidget> createState() => _BodySilhouetteWidgetState();
}

class _BodySilhouetteWidgetState extends State<BodySilhouetteWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late _Measures _from;
  late _Measures _to;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _to   = _Measures.fromMap(widget.measurements);
    _from = _to;
    _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(BodySilhouetteWidget old) {
    super.didUpdateWidget(old);
    if (old.measurements != widget.measurements) {
      _from = _from.lerp(_to, _ctrl.value);
      _to   = _Measures.fromMap(widget.measurements);
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_ctrl.value);
          final m = _from.lerp(_to, t);
          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: SizedBox(
                        width: w * 0.42,
                        height: h,
                        child: CustomPaint(painter: _BodyPainter(measures: m)),
                      ),
                    ),
                  ),
                  ..._buildLabels(m, w, h),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildLabels(_Measures m, double w, double h) {
    final cx = w * 0.50;
    final u  = (w * 0.42) * 0.5;

    double hw(double ref, double measured, double frac) {
      final norm = (measured / ref).clamp(0.70, 1.40);
      return u * frac * norm;
    }

    final sideW     = (w * 0.29 - 4).clamp(48.0, 120.0);
    final shoulderX = cx - hw(114.0, m.shoulder, 0.76);
    final chestX    = cx + hw( 97.0, m.chest,    0.58);
    final waistX    = cx - hw( 84.0, m.waist,    0.38);
    final hipX      = cx - hw( 96.0, m.hips,     0.60);
    final thighX    = cx + hw( 57.0, m.thigh,    0.29);
    final calfX     = cx + hw( 37.0, m.calf,     0.22);

    Widget leftLabel(String label, String value, double y, double silX) {
      final top = (y - 14).clamp(0.0, h - 28);
      return Positioned(
        top: top, left: 0, right: (w - silX).clamp(0.0, w),
        child: Row(children: [
          SizedBox(width: sideW,
              child: _labelCol(label, value, CrossAxisAlignment.end)),
          const Expanded(
              child: CustomPaint(painter: _LinePainter(fromLeft: true))),
        ]),
      );
    }

    Widget rightLabel(String label, String value, double y, double silX) {
      final top = (y - 14).clamp(0.0, h - 28);
      return Positioned(
        top: top, left: silX, right: 0,
        child: Row(children: [
          const Expanded(
              child: CustomPaint(painter: _LinePainter(fromLeft: false))),
          SizedBox(width: sideW,
              child: _labelCol(label, value, CrossAxisAlignment.start)),
        ]),
      );
    }

    return [
      leftLabel('Плечи',  '${m.shoulder.toStringAsFixed(0)} см', h * 0.195, shoulderX),
      leftLabel('Талия',  '${m.waist.toStringAsFixed(0)} см',    h * 0.430, waistX),
      leftLabel('Бёдра',  '${m.hips.toStringAsFixed(0)} см',     h * 0.530, hipX),
      rightLabel('Грудь',  '${m.chest.toStringAsFixed(0)} см',   h * 0.290, chestX),
      rightLabel('Бедро',  '${m.thigh.toStringAsFixed(0)} см',   h * 0.648, thighX),
      rightLabel('Голень', '${m.calf.toStringAsFixed(0)} см',    h * 0.835, calfX),
    ];
  }

  Widget _labelCol(String label, String value, CrossAxisAlignment align) {
    return Column(
      crossAxisAlignment: align,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 9, height: 1.1)),
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.1)),
      ],
    );
  }
}

// ─── Line painter ─────────────────────────────────────────────────────────────

class _LinePainter extends CustomPainter {
  final bool fromLeft;
  const _LinePainter({required this.fromLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.45)
      ..strokeWidth = 1.0;
    final cy   = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
    final dotX = fromLeft ? size.width : 0.0;
    canvas.drawCircle(
        Offset(dotX, cy), 2.5, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_LinePainter old) => false;
}

// ─── Body CustomPainter ───────────────────────────────────────────────────────

class _BodyPainter extends CustomPainter {
  final _Measures measures;
  const _BodyPainter({required this.measures});

  static const _refShoulder = 114.0;
  static const _refChest    =  97.0;
  static const _refWaist    =  84.0;
  static const _refHips     =  96.0;
  static const _refThigh    =  57.0;
  static const _refCalf     =  37.0;

  double _norm(double val, double ref) => (val / ref).clamp(0.70, 1.40);

  @override
  void paint(Canvas canvas, Size size) {
    final w  = size.width;
    final h  = size.height;
    final cx = w / 2.0;

    final sn   = _norm(measures.shoulder, _refShoulder);
    final cn   = _norm(measures.chest,    _refChest);
    final wn   = _norm(measures.waist,    _refWaist);
    final hn   = _norm(measures.hips,     _refHips);
    final tn   = _norm(measures.thigh,    _refThigh);
    final caln = _norm(measures.calf,     _refCalf);

    // Half-widths
    final headRX     = h * 0.060;
    final headRY     = h * 0.068;
    final neckHW     = cx * 0.115;
    final shoulderHW = cx * 0.76  * sn;
    final chestHW    = cx * 0.58  * cn;
    final waistHW    = cx * 0.38  * wn;
    final hipHW      = cx * 0.60  * hn;
    final thighHW    = cx * 0.29  * tn;
    final kneeHW     = cx * 0.21;
    final calfHW     = cx * 0.22  * caln;
    final ankleHW    = cx * 0.11;

    // Y positions
    final headCY    = h * 0.063;
    final neckBotY  = h * 0.170;
    final shoulderY = h * 0.190;
    final armpitY   = h * 0.285;
    final waistY    = h * 0.430;
    final hipTopY   = h * 0.468;
    final hipMaxY   = h * 0.528;
    final crotchY   = h * 0.562;
    final kneeY     = h * 0.728;
    final calfMaxY  = h * 0.830;
    final ankleY    = h * 0.908;
    final footY     = h * 0.963;
    final legGap    = cx * 0.08;

    // ── Paint styles ──────────────────────────────────────────────────────────
    final bodyFill = Paint()
      ..color = AppColors.surface
      ..style  = PaintingStyle.fill;
    final bodyStroke = Paint()
      ..color      = AppColors.accent.withValues(alpha: 0.72)
      ..style      = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap  = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final muscleLine = Paint()
      ..color      = AppColors.accent.withValues(alpha: 0.32)
      ..style      = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap  = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ── Draw order: arms → torso → legs → head+neck → deltoids → detail lines

    // Arms
    for (final s in [1.0, -1.0]) {
      final arm = _buildArm(cx: cx, h: h, s: s, shoulderHW: shoulderHW);
      canvas.drawPath(arm, bodyFill);
      canvas.drawPath(arm, bodyStroke);
      _drawArmDetails(canvas, cx, h, s, shoulderHW, armpitY, muscleLine);
    }

    // Torso
    final torso = _buildTorso(cx: cx, h: h,
      neckHW: neckHW, shoulderHW: shoulderHW, chestHW: chestHW,
      waistHW: waistHW, hipHW: hipHW, thighHW: thighHW, legGap: legGap,
      neckBotY: neckBotY, shoulderY: shoulderY, armpitY: armpitY,
      waistY: waistY, hipTopY: hipTopY, hipMaxY: hipMaxY, crotchY: crotchY,
    );
    canvas.drawPath(torso, bodyFill);
    canvas.drawPath(torso, bodyStroke);

    // Legs
    for (final s in [1.0, -1.0]) {
      final leg = _buildLeg(cx: cx, s: s,
        thighHW: thighHW, kneeHW: kneeHW, calfHW: calfHW, ankleHW: ankleHW,
        legGap: legGap, crotchY: crotchY, kneeY: kneeY,
        calfMaxY: calfMaxY, ankleY: ankleY, footY: footY, h: h,
      );
      canvas.drawPath(leg, bodyFill);
      canvas.drawPath(leg, bodyStroke);
    }

    // Head (oval)
    final headRect = Rect.fromCenter(
      center: Offset(cx, headCY),
      width:  headRX * 2.1,
      height: headRY * 2.2,
    );
    canvas.drawOval(headRect, bodyFill);
    canvas.drawOval(headRect, bodyStroke);

    // Ear bumps
    for (final s in [-1.0, 1.0]) {
      final eR = headRX * 0.22;
      final eX = cx + s * headRX * 1.02;
      final eY = headCY + headRY * 0.05;
      canvas.drawCircle(Offset(eX, eY), eR, bodyFill);
      canvas.drawArc(
        Rect.fromCenter(center: Offset(eX, eY), width: eR * 2, height: eR * 2),
        s > 0 ? -1.3 : 1.85,
        2.8,
        false,
        bodyStroke,
      );
    }

    // Neck
    final neckTopY = headCY + headRY * 0.88;
    canvas.drawRect(
      Rect.fromLTRB(cx - neckHW, neckTopY, cx + neckHW, neckBotY + 2),
      bodyFill,
    );
    canvas.drawLine(Offset(cx - neckHW, neckTopY), Offset(cx - neckHW, neckBotY), bodyStroke);
    canvas.drawLine(Offset(cx + neckHW, neckTopY), Offset(cx + neckHW, neckBotY), bodyStroke);

    // Deltoid caps at shoulder joints
    for (final s in [1.0, -1.0]) {
      final delCX = cx + s * shoulderHW * 0.91;
      final delCY = shoulderY + h * 0.020;
      final delW  = shoulderHW * 0.30;
      final delH  = h * 0.058;
      final delRect = Rect.fromCenter(
        center: Offset(delCX, delCY), width: delW, height: delH,
      );
      canvas.drawOval(delRect, bodyFill);
      canvas.drawOval(delRect, bodyStroke);
    }

    // ── Muscle detail lines ────────────────────────────────────────────────────

    // Trapezius lines (neck to shoulder)
    _drawTraps(canvas, cx, h, neckHW, shoulderHW, shoulderY, neckBotY, muscleLine);

    // Pectoral outlines
    _drawPecs(canvas, cx, h, chestHW, armpitY, muscleLine);

    // Abs + obliques
    _drawAbs(canvas, cx, h, chestHW, waistHW, armpitY, waistY, crotchY, muscleLine);

    // Quad definition
    _drawQuads(canvas, cx, h, thighHW, kneeHW, legGap, crotchY, kneeY, muscleLine);

    // Calf separation
    _drawCalves(canvas, cx, h, calfHW, legGap, kneeY, calfMaxY, ankleY, muscleLine);
  }

  // ── Trapezius ───────────────────────────────────────────────────────────────

  void _drawTraps(Canvas canvas, double cx, double h, double neckHW,
      double shoulderHW, double shoulderY, double neckBotY, Paint p) {
    for (final s in [1.0, -1.0]) {
      final trap = Path()
        ..moveTo(cx + s * neckHW * 1.1, neckBotY + h * 0.005)
        ..cubicTo(
          cx + s * neckHW * 2.2,       neckBotY + h * 0.010,
          cx + s * shoulderHW * 0.62,  shoulderY - h * 0.005,
          cx + s * shoulderHW * 0.72,  shoulderY + h * 0.012,
        );
      canvas.drawPath(trap, p);
    }
  }

  // ── Pectorals ───────────────────────────────────────────────────────────────

  void _drawPecs(Canvas canvas, double cx, double h, double chestHW,
      double armpitY, Paint p) {
    final pecTop = armpitY - h * 0.005;
    final pecBot = armpitY + h * 0.115;

    for (final s in [1.0, -1.0]) {
      final pec = Path()
        ..moveTo(cx + s * cx * 0.05, pecTop + h * 0.005)
        ..cubicTo(
          cx + s * chestHW * 0.30, pecTop - h * 0.018,
          cx + s * chestHW * 0.80, pecTop - h * 0.008,
          cx + s * chestHW * 0.93, pecTop + h * 0.010,
        )
        ..cubicTo(
          cx + s * chestHW * 1.00, pecTop + h * 0.040,
          cx + s * chestHW * 0.96, pecBot - h * 0.010,
          cx + s * chestHW * 0.88, pecBot,
        )
        ..cubicTo(
          cx + s * chestHW * 0.55, pecBot + h * 0.018,
          cx + s * cx * 0.15,      pecBot + h * 0.010,
          cx + s * cx * 0.05,      pecBot - h * 0.005,
        )
        ..close();
      canvas.drawPath(pec, p);
    }

    // Sternum center line
    canvas.drawLine(
      Offset(cx, pecTop),
      Offset(cx, pecBot + h * 0.005),
      p,
    );
  }

  // ── Abs + obliques ──────────────────────────────────────────────────────────

  void _drawAbs(Canvas canvas, double cx, double h, double chestHW,
      double waistHW, double armpitY, double waistY, double crotchY, Paint p) {
    final absTop = armpitY + h * 0.118;
    final absBot = crotchY - h * 0.038;
    final rows   = 4;
    final rowH   = (absBot - absTop) / rows;

    // Vertical center line
    canvas.drawLine(Offset(cx, absTop), Offset(cx, absBot), p);

    // Horizontal dividers (taper from chest to waist)
    for (int i = 1; i <= rows; i++) {
      final y = absTop + rowH * i;
      final t = i / rows;
      // interpolate half-width: near pecs = ~chestHW*0.55, near hips = ~waistHW*0.85
      final hw = chestHW * 0.55 * (1 - t) + waistHW * 0.85 * t;
      canvas.drawLine(Offset(cx - hw, y), Offset(cx + hw, y), p);
    }

    // Oblique curves (serratus / external oblique)
    for (final s in [1.0, -1.0]) {
      final obl = Path()
        ..moveTo(cx + s * chestHW * 0.60, armpitY + h * 0.095)
        ..cubicTo(
          cx + s * chestHW * 0.70,  armpitY + h * 0.15,
          cx + s * waistHW * 1.12,  waistY - h * 0.040,
          cx + s * waistHW * 1.08,  waistY + h * 0.030,
        );
      canvas.drawPath(obl, p);
    }
  }

  // ── Arm detail lines (bicep / forearm) ─────────────────────────────────────

  void _drawArmDetails(Canvas canvas, double cx, double h, double s,
      double shoulderHW, double armpitY, Paint p) {
    // Bicep peak line (inner arm)
    final bLine = Path()
      ..moveTo(cx + s * (shoulderHW - cx * 0.28), h * 0.205)
      ..cubicTo(
        cx + s * cx * 0.50,  h * 0.310,
        cx + s * cx * 0.50,  h * 0.390,
        cx + s * cx * 0.495, h * 0.480,
      );
    canvas.drawPath(bLine, p);
  }

  // ── Quads ────────────────────────────────────────────────────────────────────

  void _drawQuads(Canvas canvas, double cx, double h, double thighHW,
      double kneeHW, double legGap, double crotchY, double kneeY, Paint p) {
    for (final s in [1.0, -1.0]) {
      // Outer quad separation
      final outer = Path()
        ..moveTo(cx + s * (thighHW * 0.72 + legGap * 0.25), crotchY + h * 0.038)
        ..cubicTo(
          cx + s * (thighHW * 0.88 + legGap * 0.1), crotchY + h * 0.10,
          cx + s * kneeHW * 1.08,                    kneeY   - h * 0.08,
          cx + s * kneeHW * 0.93,                    kneeY   - h * 0.025,
        );
      canvas.drawPath(outer, p);

      // Vastus medialis "teardrop" — inner quad head above knee
      final vmCX = cx + s * (legGap * 0.65 + thighHW * 0.10);
      final vmCY = kneeY - h * 0.072;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(vmCX, vmCY),
          width:  thighHW * 0.38,
          height: h * 0.072,
        ),
        p,
      );

      // Inner thigh separation line
      final inner = Path()
        ..moveTo(cx + s * (legGap * 0.35 + thighHW * 0.06), crotchY + h * 0.020)
        ..cubicTo(
          cx + s * (legGap * 0.55 + thighHW * 0.04), crotchY + h * 0.08,
          cx + s * (legGap * 0.90),                  kneeY   - h * 0.09,
          cx + s * (legGap * 1.08),                  kneeY   - h * 0.025,
        );
      canvas.drawPath(inner, p);
    }
  }

  // ── Calves ───────────────────────────────────────────────────────────────────

  void _drawCalves(Canvas canvas, double cx, double h, double calfHW,
      double legGap, double kneeY, double calfMaxY, double ankleY, Paint p) {
    for (final s in [1.0, -1.0]) {
      final sepX = cx + s * (calfHW * 0.20 + legGap * 0.48);
      final calfSep = Path()
        ..moveTo(sepX, kneeY  + h * 0.025)
        ..cubicTo(
          sepX + s * calfHW * 0.04, kneeY    + h * 0.10,
          sepX + s * calfHW * 0.03, calfMaxY - h * 0.06,
          sepX,                     calfMaxY - h * 0.030,
        );
      canvas.drawPath(calfSep, p);
    }
  }

  // ── Base shapes (torso, arms, legs) ──────────────────────────────────────────

  Path _buildTorso({
    required double cx, required double h,
    required double neckHW, required double shoulderHW,
    required double chestHW, required double waistHW,
    required double hipHW, required double thighHW,
    required double legGap,
    required double neckBotY, required double shoulderY,
    required double armpitY, required double waistY,
    required double hipTopY, required double hipMaxY,
    required double crotchY,
  }) {
    final torso = Path()..moveTo(cx + neckHW, neckBotY);
    torso.cubicTo(cx + neckHW * 2.5,       neckBotY,
                  cx + shoulderHW * 0.95,  shoulderY - h * 0.008,
                  cx + shoulderHW,         shoulderY);
    torso.cubicTo(cx + shoulderHW * 1.04,  shoulderY + h * 0.04,
                  cx + chestHW    * 1.05,  armpitY   - h * 0.02,
                  cx + chestHW,            armpitY);
    torso.cubicTo(cx + chestHW    * 0.97,  armpitY   + h * 0.05,
                  cx + waistHW   * 1.08,  waistY    - h * 0.05,
                  cx + waistHW,            waistY);
    torso.cubicTo(cx + waistHW   * 0.98,  waistY    + h * 0.025,
                  cx + hipHW,              hipTopY,
                  cx + hipHW,              hipMaxY);
    torso.cubicTo(cx + hipHW    * 0.97,              hipMaxY   + h * 0.02,
                  cx + thighHW + legGap   * 1.4,     crotchY   - h * 0.015,
                  cx + thighHW + legGap,              crotchY);
    torso.cubicTo(cx + thighHW * 0.45 + legGap, crotchY + h * 0.015,
                  cx + legGap * 1.4,             crotchY + h * 0.026,
                  cx + legGap * 0.25,            crotchY + h * 0.020);
    torso.quadraticBezierTo(cx,            crotchY + h * 0.032,
                            cx - legGap * 0.25, crotchY + h * 0.020);
    torso.cubicTo(cx - legGap * 1.4,             crotchY + h * 0.026,
                  cx - thighHW * 0.45 - legGap, crotchY + h * 0.015,
                  cx - thighHW - legGap,          crotchY);
    torso.cubicTo(cx - thighHW - legGap * 1.4,   crotchY   - h * 0.015,
                  cx - hipHW   * 0.97,             hipMaxY   + h * 0.02,
                  cx - hipHW,                      hipMaxY);
    torso.cubicTo(cx - hipHW,                     hipTopY,
                  cx - waistHW * 0.98,            waistY    + h * 0.025,
                  cx - waistHW,                    waistY);
    torso.cubicTo(cx - waistHW * 1.08,            waistY    - h * 0.05,
                  cx - chestHW * 0.97,            armpitY   + h * 0.05,
                  cx - chestHW,                    armpitY);
    torso.cubicTo(cx - chestHW    * 1.05,  armpitY   - h * 0.02,
                  cx - shoulderHW * 1.04,  shoulderY + h * 0.04,
                  cx - shoulderHW,         shoulderY);
    torso.cubicTo(cx - shoulderHW * 0.95,  shoulderY - h * 0.008,
                  cx - neckHW * 2.5,       neckBotY,
                  cx - neckHW,             neckBotY);
    torso.close();
    return torso;
  }

  Path _buildArm({
    required double cx, required double h, required double s,
    required double shoulderHW,
  }) {
    final topY = h * 0.200;
    final midY = h * 0.370;
    final elbY = h * 0.490;
    final wriY = h * 0.690;

    final oTop = shoulderHW;
    final iTop = shoulderHW - cx * 0.30;
    final oMid = cx * 0.640;
    final iMid = cx * 0.470;
    final oElb = cx * 0.680;
    final iElb = cx * 0.530;
    final oWri = cx * 0.560;
    final iWri = cx * 0.440;
    final tipX = (oWri + iWri) / 2;
    final tipY = wriY + h * 0.026;

    final p = Path()..moveTo(cx + s * oTop, topY);
    p.cubicTo(cx + s * oTop,        topY + h * 0.04,
              cx + s * oMid * 1.02, midY - h * 0.02,
              cx + s * oMid,        midY);
    p.cubicTo(cx + s * oMid * 0.99, midY + h * 0.02,
              cx + s * oElb * 1.02, elbY - h * 0.02,
              cx + s * oElb,        elbY);
    p.cubicTo(cx + s * oElb * 0.98, elbY + h * 0.02,
              cx + s * oWri * 1.01, wriY - h * 0.02,
              cx + s * oWri,        wriY);
    p.quadraticBezierTo(cx + s * tipX, tipY, cx + s * iWri, wriY);
    p.cubicTo(cx + s * iWri,        wriY - h * 0.02,
              cx + s * iElb * 1.00, elbY + h * 0.02,
              cx + s * iElb,        elbY);
    p.cubicTo(cx + s * iElb * 1.00, elbY - h * 0.02,
              cx + s * iMid * 1.00, midY + h * 0.02,
              cx + s * iMid,        midY);
    p.cubicTo(cx + s * iMid,        midY - h * 0.02,
              cx + s * iTop,        topY + h * 0.04,
              cx + s * iTop,        topY);
    p.close();
    return p;
  }

  Path _buildLeg({
    required double cx, required double s,
    required double thighHW, required double kneeHW,
    required double calfHW, required double ankleHW,
    required double legGap,
    required double crotchY, required double kneeY,
    required double calfMaxY, required double ankleY,
    required double footY, required double h,
  }) {
    final p = Path()..moveTo(cx + s * (thighHW + legGap), crotchY);
    p.cubicTo(cx + s * (thighHW + legGap * 0.5), crotchY + h * 0.03,
              cx + s * thighHW  * 1.04,           kneeY   - h * 0.06,
              cx + s * kneeHW,                    kneeY);
    p.cubicTo(cx + s * kneeHW  * 1.03, kneeY    + h * 0.02,
              cx + s * calfHW  * 1.04, calfMaxY - h * 0.02,
              cx + s * calfHW,         calfMaxY);
    p.cubicTo(cx + s * calfHW  * 0.95, calfMaxY + h * 0.04,
              cx + s * ankleHW * 1.04, ankleY,
              cx + s * ankleHW,        ankleY);
    p.lineTo(cx + s * ankleHW,        footY);
    p.lineTo(cx + s * legGap  * 0.35, footY);
    p.lineTo(cx + s * legGap  * 0.35, ankleY);
    p.cubicTo(cx + s * legGap * 0.5,  calfMaxY - h * 0.02,
              cx + s * legGap * 1.1,  kneeY    + h * 0.03,
              cx + s * legGap * 1.1,  kneeY);
    p.cubicTo(cx + s * legGap * 1.2,             kneeY    - h * 0.04,
              cx + s * (thighHW * 0.25 + legGap), crotchY + h * 0.04,
              cx + s * legGap  * 0.25,             crotchY + h * 0.020);
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.measures.shoulder != measures.shoulder ||
      old.measures.chest    != measures.chest    ||
      old.measures.waist    != measures.waist    ||
      old.measures.hips     != measures.hips     ||
      old.measures.thigh    != measures.thigh    ||
      old.measures.calf     != measures.calf;
}
