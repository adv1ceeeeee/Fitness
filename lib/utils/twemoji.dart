import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders an emoji as a bundled Twemoji SVG for consistent, high-quality
/// cross-platform display instead of relying on the host OS emoji font.
///
/// Usage: `Twemoji('🔥', size: 20)`
///
/// If the emoji is not bundled, falls back to the system font so nothing
/// breaks — just that particular glyph reverts to OS rendering.
class Twemoji extends StatelessWidget {
  final String emoji;
  final double size;

  const Twemoji(this.emoji, {this.size = 16, super.key});

  @override
  Widget build(BuildContext context) {
    final asset = _assetFor(emoji);
    if (asset == null) {
      return Text(
        emoji,
        style: TextStyle(fontSize: size, height: 1.0),
      );
    }
    final fallback = Text(
      emoji,
      style: TextStyle(fontSize: size, height: 1.0),
    );
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      // Asset bundle on Windows can momentarily report missing-or-empty for
      // SVGs during a fresh build, and Twemoji has no business crashing the
      // UI over that — fall back to the system-font glyph instead.
      placeholderBuilder: (_) => fallback,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  /// The set of codepoints we bundle under `assets/emojis/`. Keep in sync
  /// with the filenames on disk.
  static const _bundled = {
    '1f525',            // 🔥 fire
    '1f3c6',            // 🏆 trophy
    '1f4aa',            // 💪 flexed biceps
    '1f3af',            // 🎯 direct hit
    '26a1',             // ⚡ high voltage
    '1f4af',            // 💯 hundred points
    '1f31f',            // 🌟 glowing star
    '1f5d3',            // 🗓️ spiral calendar
    '1f947',            // 🥇 1st place medal
    '1f396',            // 🎖️ military medal
    '1f680',            // 🚀 rocket
    '2600',             // ☀️ sun
    '1f3d6',            // 🏖️ beach with umbrella
    '1f4ca',            // 📊 bar chart
    '1f3cb',            // 🏋 person lifting weights (used for all variants)
    '1f4c8',            // 📈 chart increasing
    '1f6e1',            // 🛡️ shield
    '1f389',            // 🎉 party popper
    '1f4e6',            // 📦 package
    '1f4c5',            // 📅 calendar
  };

  /// Resolve an emoji string to its bundled asset path. Strips variation
  /// selectors (FE0F) and ZWJ joiners to normalize on the base codepoint —
  /// the weightlifter family (🏋 🏋️ 🏋️‍♂️ 🏋️‍♀️) all map to the same asset,
  /// which is fine for our purposes.
  static String? _assetFor(String emoji) {
    if (emoji.isEmpty) return null;
    final runes = emoji.runes
        .where((r) => r != 0xFE0F && r != 0x200D)
        .toList();
    if (runes.isEmpty) return null;
    final code = runes.first.toRadixString(16);
    if (!_bundled.contains(code)) return null;
    return 'assets/emojis/$code.svg';
  }
}
