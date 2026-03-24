import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sportwai/config/avatar_config.dart';
import 'package:sportwai/config/theme.dart';

/// Отображает аватар пользователя:
/// - null или "default_N" → иконка из kDefaultAvatars
/// - URL (http/https) → NetworkImage
/// - иначе → первая буква строки
class AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final String? fallbackLetter;

  const AvatarWidget({
    super.key,
    this.avatarUrl,
    this.radius = 40,
    this.fallbackLetter,
  });

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;

    // Default icon avatar
    if (url == null || url.startsWith('default_')) {
      final option = avatarById(url) ?? kDefaultAvatars[0];
      return CircleAvatar(
        radius: radius,
        backgroundColor: option.color.withValues(alpha: 0.25),
        child: Icon(
          option.icon,
          size: radius * 0.9,
          color: option.color,
        ),
      );
    }

    // Network image (custom photo) — cached on disk
    if (url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        imageBuilder: (_, image) => CircleAvatar(
          radius: radius,
          backgroundImage: image,
          backgroundColor: AppColors.card,
        ),
        placeholder: (_, __) => CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.surface,
        ),
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.accent.withValues(alpha: 0.3),
          child: Text(
            fallbackLetter?.isNotEmpty == true
                ? fallbackLetter![0].toUpperCase()
                : '?',
            style: TextStyle(
              fontSize: radius * 0.7,
              color: AppColors.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // Fallback: letter
    final letter = fallbackLetter?.isNotEmpty == true
        ? fallbackLetter![0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.accent.withValues(alpha: 0.3),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: radius * 0.7,
          color: AppColors.accent,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
