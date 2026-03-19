class Exercise {
  final String id;
  final String name;
  final String? nameRu;
  final String category;
  final String? description;
  final String? descriptionRu;
  final String? imageUrl;
  final bool isStandard;
  final String? userId;
  final bool isFavorite;
  final String? gifUrl;

  Exercise({
    required this.id,
    required this.name,
    this.nameRu,
    required this.category,
    this.description,
    this.descriptionRu,
    this.imageUrl,
    this.isStandard = true,
    this.userId,
    this.isFavorite = false,
    this.gifUrl,
  });

  String get displayName => nameRu ?? name;

  bool get isCustom => !isStandard && userId != null;

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      name: json['name'] as String,
      nameRu: json['name_ru'] as String?,
      category: json['category'] as String,
      description: json['description'] as String?,
      descriptionRu: json['description_ru'] as String?,
      imageUrl: json['image_url'] as String?,
      isStandard: json['is_standard'] as bool? ?? true,
      userId: json['user_id'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      gifUrl: json['gif_url'] as String?,
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
