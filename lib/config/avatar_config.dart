import 'package:flutter/material.dart';

class AvatarOption {
  final String id;
  final IconData icon;
  final Color color;
  final String label;

  const AvatarOption({
    required this.id,
    required this.icon,
    required this.color,
    required this.label,
  });
}

const List<AvatarOption> kDefaultAvatars = [
  AvatarOption(
    id: 'default_0',
    icon: Icons.fitness_center,
    color: Color(0xFF4CAF50),
    label: 'Штанга',
  ),
  AvatarOption(
    id: 'default_1',
    icon: Icons.directions_run,
    color: Color(0xFF2196F3),
    label: 'Бег',
  ),
  AvatarOption(
    id: 'default_2',
    icon: Icons.directions_bike,
    color: Color(0xFFFF9800),
    label: 'Велосипед',
  ),
  AvatarOption(
    id: 'default_3',
    icon: Icons.sports_basketball,
    color: Color(0xFFE91E63),
    label: 'Баскетбол',
  ),
  AvatarOption(
    id: 'default_4',
    icon: Icons.pool,
    color: Color(0xFF00BCD4),
    label: 'Плавание',
  ),
  AvatarOption(
    id: 'default_5',
    icon: Icons.sports_mma,
    color: Color(0xFFF44336),
    label: 'Бокс',
  ),
  AvatarOption(
    id: 'default_6',
    icon: Icons.self_improvement,
    color: Color(0xFF9C27B0),
    label: 'Йога',
  ),
  AvatarOption(
    id: 'default_7',
    icon: Icons.sports_soccer,
    color: Color(0xFF607D8B),
    label: 'Футбол',
  ),
  AvatarOption(
    id: 'default_8',
    icon: Icons.sports_gymnastics,
    color: Color(0xFFFF5722),
    label: 'Гимнастика',
  ),
  AvatarOption(
    id: 'default_9',
    icon: Icons.emoji_events,
    color: Color(0xFFFFC107),
    label: 'Чемпион',
  ),
];

AvatarOption? avatarById(String? id) {
  if (id == null) return null;
  try {
    return kDefaultAvatars.firstWhere((a) => a.id == id);
  } catch (_) {
    return null;
  }
}
