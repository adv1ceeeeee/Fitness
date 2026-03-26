import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/screens/profile/body_silhouette_widget.dart';

// ─── Pose definition ──────────────────────────────────────────────────────────

enum BodyPose {
  relaxed(
    label: 'Стоя',
    icon: Icons.accessibility_new_outlined,
    animationName: null,
  ),
  doubleBicep(
    label: 'Двойной бицепс',
    icon: Icons.fitness_center_outlined,
    animationName: 'Double Bicep Flex',
  );

  final String label;
  final IconData icon;
  final String? animationName;
  const BodyPose(
      {required this.label,
      required this.icon,
      required this.animationName});
}

// ─── Main widget ──────────────────────────────────────────────────────────────

class Body3DWidget extends StatefulWidget {
  final Map<String, dynamic>? measurements;

  static const String _modelAsset = 'assets/models/body.glb';
  static const String _jsAsset = 'assets/models/model-viewer.min.js';

  const Body3DWidget({super.key, this.measurements});

  @override
  State<Body3DWidget> createState() => _Body3DWidgetState();
}

class _Body3DWidgetState extends State<Body3DWidget> {
  BodyPose _pose = BodyPose.relaxed;
  WebViewController? _controller;
  bool _modelMissing = false;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // WebView file loading is only reliable on Android, iOS and macOS.
    // On Windows (desktop) webview_flutter does not support loadFile(),
    // so fall back to the silhouette widget immediately.
    if (Platform.isWindows || Platform.isLinux) {
      if (mounted) setState(() { _modelMissing = true; _initializing = false; });
      return;
    }

    // 1. Check model asset exists
    ByteData? glbData;
    try {
      glbData = await rootBundle.load(Body3DWidget._modelAsset);
    } catch (_) {
      if (mounted) {
        setState(() {
          _modelMissing = true;
          _initializing = false;
        });
      }
      return;
    }

    // 2. Prepare temp directory with all 3 files side-by-side
    //    WKWebView's loadFile() grants read access to the whole directory,
    //    so model-viewer.js and body.glb are reachable via relative paths.
    final tempDir = await getTemporaryDirectory();
    final webDir = Directory('${tempDir.path}/sportify_3d');
    await webDir.create(recursive: true);

    // Write GLB (skip if already cached with same size)
    final glbFile = File('${webDir.path}/body.glb');
    final glbBytes = glbData.buffer.asUint8List();
    if (!glbFile.existsSync() ||
        await glbFile.length() != glbBytes.length) {
      await glbFile.writeAsBytes(glbBytes, flush: true);
    }

    // Write model-viewer.min.js (skip if already cached)
    final jsFile = File('${webDir.path}/model-viewer.min.js');
    if (!jsFile.existsSync()) {
      final jsData = await rootBundle.load(Body3DWidget._jsAsset);
      await jsFile.writeAsBytes(jsData.buffer.asUint8List(), flush: true);
    }

    // Write HTML — simple relative src paths, no inline base64 needed
    const html = '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { width: 100%; height: 100%; background: #000000; overflow: hidden; }
model-viewer {
  width: 100%;
  height: 100%;
  background-color: #000000;
  --poster-color: transparent;
}
</style>
<script src="model-viewer.min.js"></script>
</head>
<body>
<model-viewer
  id="mv"
  src="body.glb"
  camera-controls
  camera-orbit="0deg 90deg 105%"
  min-camera-orbit="auto 60deg auto"
  max-camera-orbit="auto 120deg auto"
  shadow-intensity="1"
  exposure="0.9">
</model-viewer>
</body>
</html>''';

    final htmlFile = File('${webDir.path}/index.html');
    await htmlFile.writeAsString(html, flush: true);

    // 3. Load via loadFile — this calls loadFileURL:allowingReadAccessToURL:
    //    giving the page a real file:// origin with access to the whole webDir
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..loadFile(htmlFile.path);

    if (mounted) {
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    }
  }

  void _setPose(BodyPose p) {
    setState(() => _pose = p);
    if (_controller == null) return;
    const mv = "document.getElementById('mv')";
    if (p.animationName != null) {
      _controller!.runJavaScript(
          "$mv.animationName = '${p.animationName}'; $mv.play();");
    } else {
      _controller!.runJavaScript("$mv.pause(); $mv.currentTime = 0;");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: _initializing
          ? const SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()))
          : _modelMissing
              ? _NoModelPlaceholder(measurements: widget.measurements)
              : _ModelContent(
                  controller: _controller!,
                  pose: _pose,
                  onPoseChanged: _setPose,
                  measurements: widget.measurements,
                ),
    );
  }
}

// ─── Model + controls ─────────────────────────────────────────────────────────

class _ModelContent extends StatelessWidget {
  final WebViewController controller;
  final BodyPose pose;
  final ValueChanged<BodyPose> onPoseChanged;
  final Map<String, dynamic>? measurements;

  const _ModelContent({
    required this.controller,
    required this.pose,
    required this.onPoseChanged,
    this.measurements,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── WebView 3D viewer ──
        SizedBox(
          height: 440,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: WebViewWidget(controller: controller),
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

// ─── Stats row ────────────────────────────────────────────────────────────────

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
      final display =
          isWeight ? val.toStringAsFixed(1) : val.toStringAsFixed(0);
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
                'Добавь файл assets/models/body.glb\nчтобы включить 3D просмотр.',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.6),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: BodySilhouetteWidget(measurements: measurements),
        ),
      ],
    );
  }
}
