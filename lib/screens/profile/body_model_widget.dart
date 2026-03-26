import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/screens/profile/body_silhouette_widget.dart';

// ─── Pose definition ──────────────────────────────────────────────────────────

enum BodyPose {
  relaxed(
    label: 'Стоя',
    icon: Icons.accessibility_new_outlined,
    animationName: null, // T-pose / default idle
  ),
  doubleBicep(
    label: 'Двойной бицепс',
    icon: Icons.fitness_center_outlined,
    // Mixamo animation name — update if your model uses a different name
    animationName: 'Double Bicep Flex',
  );

  final String label;
  final IconData icon;
  final String? animationName;
  const BodyPose({required this.label, required this.icon, required this.animationName});
}

// ─── Main widget ──────────────────────────────────────────────────────────────

class Body3DWidget extends StatefulWidget {
  final Map<String, dynamic>? measurements;

  /// Path to the GLB model inside assets.
  /// See README-BODY-MODEL.md for instructions on getting a free model.
  static const String modelAsset = 'assets/models/body.glb';

  const Body3DWidget({super.key, this.measurements});

  @override
  State<Body3DWidget> createState() => _Body3DWidgetState();
}

class _Body3DWidgetState extends State<Body3DWidget> {
  BodyPose _pose = BodyPose.relaxed;
  late final Future<bool> _modelExists;

  @override
  void initState() {
    super.initState();
    _modelExists = _checkAsset(Body3DWidget.modelAsset);
  }

  static Future<bool> _checkAsset(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: FutureBuilder<bool>(
        future: _modelExists,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.data == false) {
            return _NoModelPlaceholder(
              measurements: widget.measurements,
            );
          }
          return _ModelContent(
            pose: _pose,
            onPoseChanged: (p) => setState(() => _pose = p),
            measurements: widget.measurements,
          );
        },
      ),
    );
  }
}

// ─── Model + controls ─────────────────────────────────────────────────────────

class _ModelContent extends StatelessWidget {
  final BodyPose pose;
  final ValueChanged<BodyPose> onPoseChanged;
  final Map<String, dynamic>? measurements;

  const _ModelContent({
    required this.pose,
    required this.onPoseChanged,
    this.measurements,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 3D viewer ──
        SizedBox(
          height: 440,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: ModelViewer(
              src: Body3DWidget.modelAsset,
              alt: '3D модель тела',
              autoRotate: false,
              cameraControls: true,
              animationName: pose.animationName,
              autoPlay: pose.animationName != null,
              backgroundColor: AppColors.background,
              // Front view default; user can rotate freely
              cameraOrbit: '0deg 90deg 105%',
              minCameraOrbit: 'auto 60deg auto',
              maxCameraOrbit: 'auto 120deg auto',
              shadowIntensity: 1,
              exposure: 0.9,
            ),
          ),
        ),

        // ── Pose switcher ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: BodyPose.values.map((p) {
              final sel = pose == p;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => onPoseChanged(p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.accent.withValues(alpha: 0.14)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: sel
                            ? Border.all(
                                color: AppColors.accent, width: 1.5)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Icon(p.icon,
                              size: 20,
                              color: sel
                                  ? AppColors.accent
                                  : AppColors.textSecondary),
                          const SizedBox(height: 4),
                          Text(
                            p.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: sel
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                              fontWeight: sel
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // ── Key stats row ──
        if (measurements != null && _hasStats(measurements!))
          _StatsRow(measurements: measurements!),

        const SizedBox(height: 12),
      ],
    );
  }

  bool _hasStats(Map<String, dynamic> m) =>
      ['weight_kg', 'body_fat_pct', 'chest_cm', 'waist_cm', 'hips_cm']
          .any((k) => m[k] != null);
}

// ─── Stats row (shown below the model) ────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final Map<String, dynamic> measurements;
  const _StatsRow({required this.measurements});

  @override
  Widget build(BuildContext context) {
    final items = <_StatItem>[];

    void add(String key, String label, String suffix,
        {bool isWeight = false}) {
      final v = measurements[key];
      if (v == null) return;
      final val = (v as num).toDouble();
      final display = isWeight ? val.toStringAsFixed(1) : val.toStringAsFixed(0);
      items.add(_StatItem(label: label, value: '$display $suffix'));
    }

    add('weight_kg', 'Вес', 'кг', isWeight: true);
    add('body_fat_pct', 'Жир', '%');
    add('chest_cm', 'Грудь', 'см');
    add('waist_cm', 'Талия', 'см');
    add('hips_cm', 'Бёдра', 'см');
    add('shoulders_cm', 'Плечи', 'см');

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items
              .map((item) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.value,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});
}

// ─── Placeholder when model file is missing ────────────────────────────────────

class _NoModelPlaceholder extends StatelessWidget {
  final Map<String, dynamic>? measurements;
  const _NoModelPlaceholder({this.measurements});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Column(
            children: [
              Icon(Icons.view_in_ar_outlined,
                  size: 48,
                  color: AppColors.accent.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              const Text(
                '3D модель не добавлена',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Чтобы использовать 3D просмотр:\n\n'
                '1. Зайди на mixamo.com (бесплатно)\n'
                '2. Выбери персонажа (например Xbot)\n'
                '3. Добавь анимации: "Idle" и "Double Bicep Flex"\n'
                '4. Скачай в формате FBX → конвертируй в GLB через Blender\n'
                '5. Сохрани файл как assets/models/body.glb\n\n'
                'Пока используется 2D силуэт.',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.6),
                textAlign: TextAlign.left,
              ),
            ],
          ),
        ),
        // Fallback: show the existing SVG silhouette
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: BodySilhouetteWidget(measurements: measurements),
        ),
      ],
    );
  }
}
