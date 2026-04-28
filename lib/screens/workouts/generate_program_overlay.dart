import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';

/// Full-screen overlay that plays a morphing "puzzle" animation while a future
/// resolves. Enforces a minimum display time so the user perceives the work as
/// substantial, even if the actual computation finishes instantly.
class GenerateProgramOverlay extends StatefulWidget {
  const GenerateProgramOverlay({super.key, required this.message});

  final String message;

  @override
  State<GenerateProgramOverlay> createState() => _GenerateProgramOverlayState();
}

class _GenerateProgramOverlayState extends State<GenerateProgramOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wrap in Material so the overlay has Material defaults — without it
    // text inside an OverlayEntry inherits a yellow-underlined "no Material"
    // debug style from Flutter on platforms with no DefaultTextStyle ancestor.
    return Material(
      color: AppColors.background.withValues(alpha: 0.96),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) => CustomPaint(
                  painter: _MorphingPuzzlePainter(_controller.value),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Анализируем профиль и подбираем упражнения…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.85),
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints four rounded tiles that translate, scale and re-arrange between
/// configurations on each loop cycle, suggesting "the AI is thinking".
class _MorphingPuzzlePainter extends CustomPainter {
  _MorphingPuzzlePainter(this.t);

  /// Loop progress in [0, 1].
  final double t;

  static const _tile = 42.0;
  static const _gap = 8.0;
  static const _radius = 10.0;

  /// Each entry is the (x, y) target position of a tile in the 2×2 grid.
  /// We morph between four arrangements on a continuous loop.
  static const List<List<Offset>> _arrangements = [
    // Square 2×2
    [Offset(0, 0), Offset(1, 0), Offset(0, 1), Offset(1, 1)],
    // Diagonal
    [Offset(0, 0), Offset(0, 1), Offset(1, 0), Offset(1, 1)],
    // Vertical line
    [Offset(0.5, -0.5), Offset(0.5, 0.5), Offset(0.5, 1.5), Offset(0.5, 2.5)],
    // Cross
    [Offset(0.5, 0), Offset(0, 0.5), Offset(1, 0.5), Offset(0.5, 1)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final segments = _arrangements.length;
    final scaledT = t * segments;
    final fromIdx = scaledT.floor() % segments;
    final toIdx = (fromIdx + 1) % segments;
    final localT = Curves.easeInOutCubic.transform(scaledT - scaledT.floor());

    final from = _arrangements[fromIdx];
    final to = _arrangements[toIdx];

    final paint = Paint()..color = AppColors.accent;
    final secondary = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.45);

    // Centre the grid in the canvas
    const cellSize = _tile + _gap;
    final originX = (size.width - cellSize) / 2;
    final originY = (size.height - cellSize) / 2;

    for (var i = 0; i < 4; i++) {
      final lerped = Offset.lerp(from[i], to[i], localT)!;
      final x = originX + lerped.dx * cellSize;
      final y = originY + lerped.dy * cellSize;

      // Subtle per-tile rotation pulse for extra "thinking" feel
      final pulse = math.sin((t + i * 0.25) * 2 * math.pi) * 0.15;
      final rect = Rect.fromLTWH(x, y, _tile, _tile);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(_radius));

      canvas.save();
      canvas.translate(x + _tile / 2, y + _tile / 2);
      canvas.rotate(pulse);
      canvas.translate(-(x + _tile / 2), -(y + _tile / 2));
      canvas.drawRRect(rrect, i.isEven ? paint : secondary);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MorphingPuzzlePainter oldDelegate) =>
      oldDelegate.t != t;
}

/// Helper: shows [GenerateProgramOverlay] on top of the navigator while [task]
/// runs. The overlay stays visible at least [minDuration] so the animation
/// doesn't flash.
Future<T> showGenerationOverlay<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() task,
  Duration minDuration = const Duration(seconds: 5),
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final entry = OverlayEntry(
    builder: (_) => GenerateProgramOverlay(message: message),
  );
  navigator.overlay!.insert(entry);

  final stopwatch = Stopwatch()..start();
  T result;
  Object? error;
  StackTrace? stackTrace;
  try {
    result = await task();
  } catch (e, st) {
    error = e;
    stackTrace = st;
    result = null as T; // unreachable; rethrown below
  }
  final remaining = minDuration - stopwatch.elapsed;
  if (remaining > Duration.zero) await Future.delayed(remaining);
  entry.remove();
  if (error != null) {
    Error.throwWithStackTrace(error, stackTrace!);
  }
  return result;
}
