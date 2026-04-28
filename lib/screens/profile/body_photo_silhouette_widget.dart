import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/providers/settings_provider.dart';

class BodyPhotoSilhouetteWidget extends StatelessWidget {
  final String? gender;
  final Map<String, dynamic>? measurements;
  final bool useCm;

  const BodyPhotoSilhouetteWidget({
    super.key,
    this.gender,
    this.measurements,
    required this.useCm,
  });

  static const double _imageAspect = 365.0 / 900.0;

  String get _asset => gender == 'female'
      ? 'assets/body/female.png'
      : 'assets/body/male.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 540,
      decoration: BoxDecoration(
        // Plain solid card — no radial gradient. The blue tint behind the
        // silhouette competed visually with the body lines and overlay tags.
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.textSecondary.withValues(alpha: 0.08),
        ),
      ),
      child: LayoutBuilder(builder: _build),
    );
  }

  Widget _build(BuildContext context, BoxConstraints c) {
    final cw = c.maxWidth;
    final ch = c.maxHeight;

    final imgH = ch - 32.0;
    final imgW = imgH * _imageAspect;
    final imgLeft = (cw - imgW) / 2;
    const imgTop = 16.0;

    double sx(double nx) => imgLeft + nx * imgW;
    double sy(double ny) => imgTop + ny * imgH;

    return Stack(children: [
      Positioned(
        left: imgLeft,
        top: imgTop,
        width: imgW,
        height: imgH,
        child: Image.asset(_asset, fit: BoxFit.contain),
      ),
      ..._buildLabels(cw, imgLeft, imgTop, imgW, imgH, sx, sy),
    ]);
  }

  // ─── Measurement labels (callouts) ─────────────────────────────────────────

  List<Widget> _buildLabels(
    double cw,
    double imgLeft,
    double imgTop,
    double imgW,
    double imgH,
    double Function(double) sx,
    double Function(double) sy,
  ) {
    final lenLabel = lengthLabel(useCm);
    final m = measurements;

    String fmt(String key) {
      if (m == null || m[key] == null) return '—';
      final cm = (m[key] as num).toDouble();
      final d = cmToDisplay(cm, useCm);
      final rounded = d % 1 == 0 ? d.toInt().toString() : d.toStringAsFixed(1);
      return '$rounded $lenLabel';
    }

    String fmtAvg(String a, String b) {
      if (m == null) return '—';
      final va = m[a] != null ? (m[a] as num).toDouble() : null;
      final vb = m[b] != null ? (m[b] as num).toDouble() : null;
      if (va == null && vb == null) return '—';
      final cm = ((va ?? vb!) + (vb ?? va!)) / 2;
      final d = cmToDisplay(cm, useCm);
      final rounded = d % 1 == 0 ? d.toInt().toString() : d.toStringAsFixed(1);
      return '$rounded $lenLabel';
    }

    // Label size & vertical bounds
    final sw = (cw * 0.24).clamp(72.0, 104.0);
    final maxTop = imgTop + imgH - 16;

    Widget leftLabel(String title, String value, double ny, double edgeNx) {
      final top = (sy(ny) - 18).clamp(imgTop - 8, maxTop);
      return Positioned(
        top: top,
        left: 0,
        right: (cw - sx(edgeNx)).clamp(0.0, cw),
        child: Row(children: [
          SizedBox(width: sw, child: _labelText(title, value, true)),
          const Expanded(
            child: SizedBox(
              height: 18,
              child: CustomPaint(painter: _LinePainter(fromLeft: true)),
            ),
          ),
        ]),
      );
    }

    Widget rightLabel(String title, String value, double ny, double edgeNx) {
      final top = (sy(ny) - 18).clamp(imgTop - 8, maxTop);
      return Positioned(
        top: top,
        left: sx(edgeNx),
        right: 0,
        child: Row(children: [
          const Expanded(
            child: SizedBox(
              height: 18,
              child: CustomPaint(painter: _LinePainter(fromLeft: false)),
            ),
          ),
          SizedBox(width: sw, child: _labelText(title, value, false)),
        ]),
      );
    }

    return [
      // Left side (line points from label to body's left edge)
      leftLabel('Плечи', fmt('shoulders_cm'), 0.18, 0.10),
      leftLabel(
          'Рука', fmtAvg('right_arm_cm', 'left_arm_cm'), 0.28, 0.09),
      leftLabel('Талия', fmt('waist_cm'), 0.40, 0.30),
      leftLabel('Бедро',
          fmtAvg('right_thigh_cm', 'left_thigh_cm'), 0.62, 0.36),
      leftLabel('Голень',
          fmtAvg('right_calf_cm', 'left_calf_cm'), 0.84, 0.40),
      // Right side
      rightLabel('Шея', fmt('neck_cm'), 0.135, 0.56),
      rightLabel('Грудь', fmt('chest_cm'), 0.25, 0.75),
      rightLabel('Предпл.',
          fmtAvg('right_forearm_cm', 'left_forearm_cm'), 0.38, 0.92),
      rightLabel('Бёдра', fmt('hips_cm'), 0.47, 0.72),
    ];
  }

  Widget _labelText(String title, String value, bool alignEnd) {
    final align =
        alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.15,
            letterSpacing: 0.3,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

// ─── Callout line painter ────────────────────────────────────────────────────

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
    canvas.drawCircle(
      Offset(fromLeft ? size.width : 0.0, cy),
      2.5,
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => false;
}
