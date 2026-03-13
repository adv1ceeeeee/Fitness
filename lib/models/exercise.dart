class Exercise {
  final String id;
  final String name;
  final String category;
  final String? description;
  final String? imageUrl;
  final bool isStandard;
  final String? userId;
  final bool isFavorite;

  Exercise({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    this.imageUrl,
    this.isStandard = true,
    this.userId,
    this.isFavorite = false,
  });

  bool get isCustom => !isStandard && userId != null;

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      isStandard: json['is_standard'] as bool? ?? true,
      userId: json['user_id'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'description': description,
        'image_url': imageUrl,
        'is_standard': isStandard,
        if (userId != null) 'user_id': userId,
      };

  static String categoryDisplayName(String category) {
    const map = {
      'chest': 'Грудь',
      'back': 'Спина',
      'legs': 'Ноги',
      'shoulders': 'Плечи',
      'arms': 'Руки',
      'cardio': 'Кардио',
      'core': 'Пресс',
    };
    return map[category] ?? category;
  }
}
