import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sportwai/config/theme.dart';

// ─── Public widget ────────────────────────────────────────────────────────────

class BodySilhouetteWidget extends StatelessWidget {
  final Map<String, dynamic>? measurements;

  const BodySilhouetteWidget({super.key, this.measurements});

  // SVG viewport dimensions (must match paths below)
  static const double _vw = 200;
  static const double _vh = 420;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 460,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(builder: _build),
    );
  }

  Widget _build(BuildContext context, BoxConstraints c) {
    final cw = c.maxWidth;
    final ch = c.maxHeight;

    // Keep SVG aspect ratio, fill height with 16px vertical padding each side
    final svgH = ch - 32.0;
    final svgW = svgH * (_vw / _vh);
    final svgLeft = (cw - svgW) / 2;
    const svgTop = 16.0;
    final scale = svgH / _vh;

    return Stack(children: [
      Positioned(
        left: svgLeft,
        top: svgTop,
        width: svgW,
        height: svgH,
        child: SvgPicture.string(_buildSvg()),
      ),
      ..._buildLabels(cw, svgLeft, svgTop, scale),
    ]);
  }

  // ─── SVG body with zone highlights ─────────────────────────────────────────

  String _buildSvg() {
    final m = measurements;
    bool has(String key) => m != null && m[key] != null;

    // Returns SVG fill attributes for a zone ellipse
    String z(bool measured) => measured
        ? 'fill="#0066FF" fill-opacity="0.40"'
        : 'fill="none"';

    // Body paths derived from the 200×420 coordinate system:
    //   cx=100, headCY=26.5, neckBotY=71.4, shoulderY=79.8, armpitY=119.7
    //   waistY=180.6, hipMaxY=221.8, crotchY=235.9, kneeY=306
    //   calfMaxY=349, ankleY=381, footY=404
    //   shoulderHW=76, chestHW=58, waistHW=38, hipHW=60
    //   thighHW=29, kneeHW=21, calfHW=22, ankleHW=11, legGap=8

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 420">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%"   stop-color="#191919"/>
      <stop offset="50%"  stop-color="#232325"/>
      <stop offset="100%" stop-color="#191919"/>
    </linearGradient>
    <linearGradient id="bgL" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%"   stop-color="#1E1E20"/>
      <stop offset="100%" stop-color="#141414"/>
    </linearGradient>
    <linearGradient id="bgR" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%"   stop-color="#141414"/>
      <stop offset="100%" stop-color="#1E1E20"/>
    </linearGradient>
  </defs>

  <!-- ── Legs (drawn first so torso covers the tops) ── -->
  <!-- Person's right leg (SVG left) -->
  <path d="M 63,235.9
           C 67,248.5 69.84,280.8 79,306
           C 78.37,314.4 77.12,340.6 78,349
           C 79.1,365.8 88.56,381 89,381
           L 89,404 L 97.2,404 L 97.2,381
           C 96,340.6 91.2,318.6 91.2,306
           C 90.4,289.2 84.75,252.7 98,244.3 Z"
        fill="url(#bgL)" stroke="#3C3E58" stroke-width="1.4"/>

  <!-- Person's left leg (SVG right) -->
  <path d="M 137,235.9
           C 133,248.5 130.16,280.8 121,306
           C 121.63,314.4 122.88,340.6 122,349
           C 120.9,365.8 111.44,381 111,381
           L 111,404 L 102.8,404 L 102.8,381
           C 104,340.6 108.8,318.6 108.8,306
           C 109.6,289.2 115.25,252.7 102,244.3 Z"
        fill="url(#bgR)" stroke="#3C3E58" stroke-width="1.4"/>

  <!-- ── Arms (drawn before torso so torso covers the tops) ── -->
  <!-- Person's right arm (SVG left) -->
  <path d="M 24,84
           C 24,100.8 34.72,147.4 36,155.4
           C 36.64,163.8 30.64,197.4 32,205.8
           C 33.36,214.2 43.44,281.4 44,289.8
           Q 50,300.7 56,289.8
           C 56,281.4 47,214.2 47,205.8
           C 47,197.4 53,163.8 53,155.4
           C 53,147.4 54,100.8 54,84 Z"
        fill="url(#bgL)" stroke="#3C3E58" stroke-width="1.4"/>

  <!-- Person's left arm (SVG right) -->
  <path d="M 176,84
           C 176,100.8 165.28,147.4 164,155.4
           C 163.36,163.8 169.36,197.4 168,205.8
           C 166.64,214.2 156.56,281.4 156,289.8
           Q 150,300.7 144,289.8
           C 144,281.4 153,214.2 153,205.8
           C 153,197.4 147,163.8 147,155.4
           C 147,147.4 146,100.8 146,84 Z"
        fill="url(#bgR)" stroke="#3C3E58" stroke-width="1.4"/>

  <!-- ── Torso ── -->
  <path d="M 111.5,71.4
           C 128.75,71.4 172.2,76.44 176,79.8
           C 179.04,96.6 160.9,111.3 158,119.7
           C 156.26,140.7 141.04,159.6 138,180.6
           C 137.24,191.1 160,196.6 160,221.8
           C 158.2,230.2 140.2,229.6 137,235.9
           C 121.05,242.2 111.2,246.8 102,244.3
           Q 100,249.3 98,244.3
           C 88.8,246.8 78.95,242.2 63,235.9
           C 59.8,229.6 41.8,230.2 40,221.8
           C 40,196.6 62.76,191.1 62,180.6
           C 58.96,159.6 43.74,140.7 42,119.7
           C 39.1,111.3 20.96,96.6 24,79.8
           C 27.8,76.44 71.25,71.4 88.5,71.4 Z"
        fill="url(#bg)" stroke="#3C3E58" stroke-width="1.4"/>

  <!-- ── Head ── -->
  <ellipse cx="100" cy="26.5" rx="26.5" ry="31.4"
           fill="url(#bg)" stroke="#3C3E58" stroke-width="1.4"/>

  <!-- ── Neck ── -->
  <rect x="88.5" y="51.6" width="23" height="21.8"
        fill="url(#bg)" stroke="#3C3E58" stroke-width="1.2"/>

  <!-- ── Deltoid caps ── -->
  <ellipse cx="169.2" cy="88.2" rx="11.4" ry="12.2"
           fill="url(#bgR)" stroke="#3C3E58" stroke-width="1.2"/>
  <ellipse cx="30.8" cy="88.2" rx="11.4" ry="12.2"
           fill="url(#bgL)" stroke="#3C3E58" stroke-width="1.2"/>

  <!-- ══════════════════════ MEASUREMENT ZONES ══════════════════════ -->
  <!-- Zones glow blue when the measurement is recorded               -->

  <!-- Neck -->
  <ellipse cx="100" cy="62" rx="11" ry="8"       ${z(has('neck_cm'))}/>

  <!-- Shoulders / traps -->
  <ellipse cx="100" cy="84" rx="72" ry="10"      ${z(has('shoulders_cm'))}/>

  <!-- Chest -->
  <ellipse cx="100" cy="122" rx="53" ry="20"     ${z(has('chest_cm'))}/>

  <!-- Waist / abs -->
  <ellipse cx="100" cy="181" rx="37" ry="15"     ${z(has('waist_cm'))}/>

  <!-- Hips -->
  <ellipse cx="100" cy="221" rx="58" ry="17"     ${z(has('hips_cm'))}/>

  <!-- Right upper arm (SVG left) -->
  <ellipse cx="37" cy="155" rx="15" ry="36"      ${z(has('right_arm_cm'))}/>
  <!-- Left upper arm (SVG right) -->
  <ellipse cx="163" cy="155" rx="15" ry="36"     ${z(has('left_arm_cm'))}/>

  <!-- Right forearm (SVG left) -->
  <ellipse cx="34" cy="232" rx="11" ry="28"      ${z(has('right_forearm_cm'))}/>
  <!-- Left forearm (SVG right) -->
  <ellipse cx="166" cy="232" rx="11" ry="28"     ${z(has('left_forearm_cm'))}/>

  <!-- Right thigh (SVG left) -->
  <ellipse cx="81" cy="285" rx="25" ry="45"      ${z(has('right_thigh_cm'))}/>
  <!-- Left thigh (SVG right) -->
  <ellipse cx="119" cy="285" rx="25" ry="45"     ${z(has('left_thigh_cm'))}/>

  <!-- Right calf (SVG left) -->
  <ellipse cx="79" cy="360" rx="17" ry="30"      ${z(has('right_calf_cm'))}/>
  <!-- Left calf (SVG right) -->
  <ellipse cx="121" cy="360" rx="17" ry="30"     ${z(has('left_calf_cm'))}/>
</svg>''';
  }

  // ─── Measurement callout labels ────────────────────────────────────────────

  List<Widget> _buildLabels(
      double cw, double svgLeft, double svgTop, double scale) {
    final m = measurements;

    String val(String key) {
      if (m == null || m[key] == null) return '—';
      return '${(m[key] as num).toStringAsFixed(0)} см';
    }

    String avg(String a, String b) {
      if (m == null) return '—';
      final va = m[a] != null ? (m[a] as num).toDouble() : null;
      final vb = m[b] != null ? (m[b] as num).toDouble() : null;
      if (va == null && vb == null) return '—';
      final v = ((va ?? vb!) + (vb ?? va!)) / 2;
      return '${v.toStringAsFixed(0)} см';
    }

    // Convert SVG coordinates to screen positions
    double sx(double svgX) => svgLeft + svgX * scale;
    double sy(double svgY) => svgTop + svgY * scale;

    final sw = (cw * 0.18).clamp(48.0, 72.0);
    const maxTop = 432.0;

    Widget leftLabel(String label, String value, double svgY, double bodyEdgeX) {
      final top = (sy(svgY) - 14).clamp(0.0, maxTop);
      return Positioned(
        top: top,
        left: 0,
        right: (cw - sx(bodyEdgeX)).clamp(0.0, cw),
        child: Row(children: [
          SizedBox(width: sw, child: _labelText(label, value, true)),
          const Expanded(child: CustomPaint(painter: _LinePainter(fromLeft: true))),
        ]),
      );
    }

    Widget rightLabel(String label, String value, double svgY, double bodyEdgeX) {
      final top = (sy(svgY) - 14).clamp(0.0, maxTop);
      return Positioned(
        top: top,
        left: sx(bodyEdgeX),
        right: 0,
        child: Row(children: [
          const Expanded(child: CustomPaint(painter: _LinePainter(fromLeft: false))),
          SizedBox(width: sw, child: _labelText(label, value, false)),
        ]),
      );
    }

    return [
      // Left side: shoulders, waist, hips
      // Body left edges (SVG x): shoulder arm outer=24, waist=62, hip=40
      leftLabel('Плечи',  val('shoulders_cm'),                     79.8,  24.0),
      leftLabel('Талия',  val('waist_cm'),                         180.6, 62.0),
      leftLabel('Бёдра',  val('hips_cm'),                          218.0, 40.0),
      // Right side: chest, thigh, calf
      // Body right edges (SVG x): chest=158, thigh outer≈122, calf outer≈122
      rightLabel('Грудь',  val('chest_cm'),                        119.7, 158.0),
      rightLabel('Бедро',  avg('right_thigh_cm', 'left_thigh_cm'), 272.0, 122.0),
      rightLabel('Голень', avg('right_calf_cm',  'left_calf_cm'),  350.0, 122.0),
    ];
  }

  Widget _labelText(String label, String value, bool alignEnd) {
    final align =
        alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
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

// ─── Callout line painter ──────────────────────────────────────────────────────

class _LinePainter extends CustomPainter {
  final bool fromLeft;
  const _LinePainter({required this.fromLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.40)
      ..strokeWidth = 1.0;
    final cy = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
    canvas.drawCircle(
      Offset(fromLeft ? size.width : 0.0, cy),
      2.5,
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => false;
}
