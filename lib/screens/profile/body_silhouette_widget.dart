import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';

// ─── Measurement data class ───────────────────────────────────────────────────

class _Measures {
  final double shoulder; // circumference cm
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
      chest: use('chest_cm', defaults.chest),
      waist: use('waist_cm', defaults.waist),
      hips: use('hips_cm', defaults.hips),
      thigh: avg('left_thigh_cm', 'right_thigh_cm', defaults.thigh),
      calf: avg('left_calf_cm', 'right_calf_cm', defaults.calf),
    );
  }

  _Measures lerp(_Measures other, double t) => _Measures(
        shoulder: _lv(shoulder, other.shoulder, t),
        chest: _lv(chest, other.chest, t),
        waist: _lv(waist, other.waist, t),
        hips: _lv(hips, other.hips, t),
        thigh: _lv(thigh, other.thigh, t),
        calf: _lv(calf, other.calf, t),
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
    _to = _Measures.fromMap(widget.measurements);
    _from = _to;
    _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(BodySilhouetteWidget old) {
    super.didUpdateWidget(old);
    if (old.measurements != widget.measurements) {
      _from = _from.lerp(_to, _ctrl.value);
      _to = _Measures.fromMap(widget.measurements);
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
      height: 400,
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
                  // Silhouette centred
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: SizedBox(
                        width: w * 0.42,
                        height: h,
                        child: CustomPaint(
                          painter: _BodyPainter(measures: m),
                        ),
                      ),
                    ),
                  ),

                  // Labels
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
    // silhouette canvas occupies 42% of w, centred → canvas left = w * 0.29
    final canvasLeft = w * 0.29;
    final canvasRight = w * 0.71;
    final cx = w * 0.50; // centre of silhouette

    // ── Reference half-widths (same fractions as _BodyPainter) ──────────────
    final u = (w * 0.42) * 0.5; // half of canvas width
    double hw(double ref, double measured, double frac) {
      final norm = (measured / ref).clamp(0.70, 1.40);
      return u * frac * norm;
    }

    final shoulderEdge = cx + hw(114.0, m.shoulder, 0.76);
    final chestEdge    = cx + hw( 97.0, m.chest,    0.58);
    final waistEdge    = cx - hw( 84.0, m.waist,    0.38); // left
    final hipEdge      = cx - hw( 96.0, m.hips,     0.60); // left
    final thighEdge    = cx + hw( 57.0, m.thigh,    0.29);
    final calfEdge     = cx + hw( 37.0, m.calf,     0.22);

    final leftLabels = <_LabelDef>[
      _LabelDef('Плечи',  '${m.shoulder.toStringAsFixed(0)} см', h * 0.195, shoulderEdge, true),
      _LabelDef('Талия',  '${m.waist.toStringAsFixed(0)} см',   h * 0.430, waistEdge,    true),
      _LabelDef('Бёдра',  '${m.hips.toStringAsFixed(0)} см',    h * 0.530, hipEdge,      true),
    ];
    final rightLabels = <_LabelDef>[
      _LabelDef('Грудь',  '${m.chest.toStringAsFixed(0)} см',   h * 0.290, chestEdge,  false),
      _LabelDef('Бедро',  '${m.thigh.toStringAsFixed(0)} см',   h * 0.648, thighEdge,  false),
      _LabelDef('Голень', '${m.calf.toStringAsFixed(0)} см',    h * 0.835, calfEdge,   false),
    ];

    return [...leftLabels, ...rightLabels].map((lbl) {
      const textH = 28.0;
      final top = (lbl.yPos - textH / 2).clamp(0.0, h - textH);

      if (lbl.isLeft) {
        return Positioned(
          top: top,
          left: 0,
          child: _LabelLeft(
            label: lbl.label,
            value: lbl.value,
            lineEndX: lbl.silhouetteX - 0,
            containerLeft: 0,
            textAreaW: canvasLeft - 4,
          ),
        );
      } else {
        return Positioned(
          top: top,
          right: 0,
          child: _LabelRight(
            label: lbl.label,
            value: lbl.value,
            lineStartX: lbl.silhouetteX - canvasRight,
            textAreaW: w - canvasRight - 4,
            totalW: w,
            silhouetteEdge: lbl.silhouetteX,
            canvasRight: canvasRight,
          ),
        );
      }
    }).toList();
  }
}

class _LabelDef {
  final String label;
  final String value;
  final double yPos;
  final double silhouetteX;
  final bool isLeft;
  const _LabelDef(this.label, this.value, this.yPos, this.silhouetteX, this.isLeft);
}

// ─── Label widgets ────────────────────────────────────────────────────────────

class _LabelLeft extends StatelessWidget {
  final String label;
  final String value;
  final double lineEndX;
  final double containerLeft;
  final double textAreaW;

  const _LabelLeft({
    required this.label,
    required this.value,
    required this.lineEndX,
    required this.containerLeft,
    required this.textAreaW,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: lineEndX,
      height: 28,
      child: Row(
        children: [
          SizedBox(
            width: textAreaW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        height: 1.1)),
                Text(value,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.1)),
              ],
            ),
          ),
          const Expanded(
            child: CustomPaint(
              painter: _LinePainter(fromLeft: true),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelRight extends StatelessWidget {
  final String label;
  final String value;
  final double lineStartX;
  final double textAreaW;
  final double totalW;
  final double silhouetteEdge;
  final double canvasRight;

  const _LabelRight({
    required this.label,
    required this.value,
    required this.lineStartX,
    required this.textAreaW,
    required this.totalW,
    required this.silhouetteEdge,
    required this.canvasRight,
  });

  @override
  Widget build(BuildContext context) {
    final lineWidth = (totalW - silhouetteEdge - 4).clamp(4.0, 80.0);
    return SizedBox(
      width: totalW - silhouetteEdge + textAreaW,
      height: 28,
      child: Row(
        children: [
          SizedBox(
            width: lineWidth,
            child: const CustomPaint(
              painter: _LinePainter(fromLeft: false),
            ),
          ),
          SizedBox(
            width: textAreaW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        height: 1.1)),
                Text(value,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final bool fromLeft;
  const _LinePainter({required this.fromLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.45)
      ..strokeWidth = 1.0;
    final cy = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
    // dot at silhouette end
    final dotX = fromLeft ? size.width : 0.0;
    canvas.drawCircle(
        Offset(dotX, cy), 2.5, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_LinePainter old) => false;
}

// ─── CustomPainter ────────────────────────────────────────────────────────────

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
    final w = size.width;
    final h = size.height;
    final cx = w / 2.0;

    final sn  = _norm(measures.shoulder, _refShoulder);
    final cn  = _norm(measures.chest,    _refChest);
    final wn  = _norm(measures.waist,    _refWaist);
    final hn  = _norm(measures.hips,     _refHips);
    final tn  = _norm(measures.thigh,    _refThigh);
    final caln = _norm(measures.calf,    _refCalf);

    // Half-widths from centre
    final headR      = h * 0.065;
    final neckHW     = cx * 0.115;
    final shoulderHW = cx * 0.76  * sn;
    final chestHW    = cx * 0.58  * cn;
    final waistHW    = cx * 0.38  * wn;
    final hipHW      = cx * 0.60  * hn;
    final thighHW    = cx * 0.29  * tn;
    final kneeHW     = cx * 0.21;
    final calfHW     = cx * 0.22  * caln;
    final ankleHW    = cx * 0.12;

    // Y positions
    final headCY    = h * 0.065;
    final neckBotY  = h * 0.175;
    final shoulderY = h * 0.195;
    final armpitY   = h * 0.290;
    final waistY    = h * 0.430;
    final hipTopY   = h * 0.470;
    final hipMaxY   = h * 0.530;
    final crotchY   = h * 0.565;
    final kneeY     = h * 0.730;
    final calfMaxY  = h * 0.835;
    final ankleY    = h * 0.910;
    final footY     = h * 0.965;

    final legGap = cx * 0.08;

    const fillColor   = AppColors.surface;
    final strokeColor = AppColors.accent.withValues(alpha: 0.65);

    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ── Head ─────────────────────────────────────────────────────────────────
    canvas.drawCircle(Offset(cx, headCY), headR, fill);
    canvas.drawCircle(Offset(cx, headCY), headR, stroke);

    // ── Neck ─────────────────────────────────────────────────────────────────
    final neckTopY = headCY + headR - 3;
    final neckRect = Rect.fromLTRB(cx - neckHW, neckTopY, cx + neckHW, neckBotY + 2);
    canvas.drawRect(neckRect, fill);
    canvas.drawLine(Offset(cx - neckHW, neckTopY), Offset(cx - neckHW, neckBotY), stroke);
    canvas.drawLine(Offset(cx + neckHW, neckTopY), Offset(cx + neckHW, neckBotY), stroke);

    // ── Torso (+ crotch) ─────────────────────────────────────────────────────
    final torso = Path()..moveTo(cx + neckHW, neckBotY);

    // Right: neck → shoulder
    torso.cubicTo(cx + neckHW * 2.5, neckBotY,
                  cx + shoulderHW * 0.95, shoulderY - h * 0.008,
                  cx + shoulderHW, shoulderY);
    // Right: shoulder → armpit
    torso.cubicTo(cx + shoulderHW * 1.04, shoulderY + h * 0.04,
                  cx + chestHW * 1.05,    armpitY - h * 0.02,
                  cx + chestHW, armpitY);
    // Right: chest → waist
    torso.cubicTo(cx + chestHW * 0.97, armpitY + h * 0.05,
                  cx + waistHW * 1.08, waistY - h * 0.05,
                  cx + waistHW, waistY);
    // Right: waist → hip
    torso.cubicTo(cx + waistHW * 0.98, waistY + h * 0.025,
                  cx + hipHW, hipTopY,
                  cx + hipHW, hipMaxY);
    // Right: hip → crotch
    torso.cubicTo(cx + hipHW * 0.97,              hipMaxY + h * 0.02,
                  cx + thighHW + legGap * 1.4,     crotchY - h * 0.015,
                  cx + thighHW + legGap,            crotchY);
    // Inner groin → crotch bottom
    torso.cubicTo(cx + thighHW * 0.45 + legGap, crotchY + h * 0.015,
                  cx + legGap * 1.4,             crotchY + h * 0.026,
                  cx + legGap * 0.25,            crotchY + h * 0.020);
    torso.quadraticBezierTo(cx, crotchY + h * 0.032, cx - legGap * 0.25, crotchY + h * 0.020);
    torso.cubicTo(cx - legGap * 1.4,             crotchY + h * 0.026,
                  cx - thighHW * 0.45 - legGap, crotchY + h * 0.015,
                  cx - thighHW - legGap,          crotchY);
    // Left: hip → crotch
    torso.cubicTo(cx - thighHW - legGap * 1.4,   crotchY - h * 0.015,
                  cx - hipHW * 0.97,              hipMaxY + h * 0.02,
                  cx - hipHW, hipMaxY);
    // Left: waist → hip
    torso.cubicTo(cx - hipHW, hipTopY,
                  cx - waistHW * 0.98, waistY + h * 0.025,
                  cx - waistHW, waistY);
    // Left: chest → waist
    torso.cubicTo(cx - waistHW * 1.08, waistY - h * 0.05,
                  cx - chestHW * 0.97, armpitY + h * 0.05,
                  cx - chestHW, armpitY);
    // Left: shoulder → armpit
    torso.cubicTo(cx - chestHW * 1.05,    armpitY - h * 0.02,
                  cx - shoulderHW * 1.04, shoulderY + h * 0.04,
                  cx - shoulderHW, shoulderY);
    // Left: neck → shoulder
    torso.cubicTo(cx - shoulderHW * 0.95, shoulderY - h * 0.008,
                  cx - neckHW * 2.5, neckBotY,
                  cx - neckHW, neckBotY);
    torso.close();

    canvas.drawPath(torso, fill);
    canvas.drawPath(torso, stroke);

    // ── Legs ─────────────────────────────────────────────────────────────────
    for (final side in [1.0, -1.0]) {
      final leg = _buildLeg(
        cx: cx, s: side,
        thighHW: thighHW, kneeHW: kneeHW,
        calfHW: calfHW, ankleHW: ankleHW,
        legGap: legGap,
        crotchY: crotchY, kneeY: kneeY,
        calfMaxY: calfMaxY, ankleY: ankleY,
        footY: footY, h: h,
      );
      canvas.drawPath(leg, fill);
      canvas.drawPath(leg, stroke);
    }
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

    // Outer thigh
    p.cubicTo(cx + s * (thighHW + legGap * 0.5), crotchY + h * 0.03,
              cx + s * thighHW * 1.04,            kneeY - h * 0.06,
              cx + s * kneeHW, kneeY);
    // Outer calf
    p.cubicTo(cx + s * kneeHW * 1.03, kneeY + h * 0.02,
              cx + s * calfHW * 1.04, calfMaxY - h * 0.02,
              cx + s * calfHW, calfMaxY);
    // Outer ankle
    p.cubicTo(cx + s * calfHW * 0.95, calfMaxY + h * 0.04,
              cx + s * ankleHW * 1.04, ankleY,
              cx + s * ankleHW, ankleY);

    p.lineTo(cx + s * ankleHW, footY);
    p.lineTo(cx + s * legGap * 0.35, footY);
    p.lineTo(cx + s * legGap * 0.35, ankleY);

    // Inner calf
    p.cubicTo(cx + s * legGap * 0.5,  calfMaxY - h * 0.02,
              cx + s * legGap * 1.1,  kneeY + h * 0.03,
              cx + s * legGap * 1.1,  kneeY);
    // Inner thigh
    p.cubicTo(cx + s * legGap * 1.2,            kneeY - h * 0.04,
              cx + s * (thighHW * 0.25 + legGap), crotchY + h * 0.04,
              cx + s * legGap * 0.25,              crotchY + h * 0.020);

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
