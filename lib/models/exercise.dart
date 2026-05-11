/// How a user enters data for an exercise during a workout.
/// - [weighted]: weight + reps + RPE (default — all strength exercises)
/// - [bodyweight]: reps + RPE only (no external load)
/// - [cardio]: time-based (no weight, no RPE) — bike, run, rowing
enum ExerciseInputMode { weighted, bodyweight, cardio }

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

  /// Movement pattern: 'press','row','fly','curl','extension','raise',
  /// 'squat','lunge','plank','cardio','other'
  final String? movementType;

  /// Difficulty: 'beginner', 'intermediate', 'advanced'
  final String? difficulty;
  final String? equipmentType;

  /// Explicit DB override: 'weighted' | 'bodyweight' | 'cardio' | null.
  /// When null, [effectiveInputMode] falls back to category/equipment.
  final String? inputMode;

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
    this.movementType,
    this.difficulty,
    this.equipmentType,
    this.inputMode,
  });

  String get displayName =>
      nameRu != null && nameRu!.trim().isNotEmpty ? nameRu!.trim() : name;

  Exercise copyWith({
    String? id,
    String? name,
    String? nameRu,
    String? category,
    String? description,
    String? descriptionRu,
    String? imageUrl,
    bool? isStandard,
    String? userId,
    bool? isFavorite,
    String? gifUrl,
    String? movementType,
    String? difficulty,
    String? equipmentType,
    String? inputMode,
  }) {
    return Exercise(
      id: id ?? this.id,
      name: name ?? this.name,
      nameRu: nameRu ?? this.nameRu,
      category: category ?? this.category,
      description: description ?? this.description,
      descriptionRu: descriptionRu ?? this.descriptionRu,
      imageUrl: imageUrl ?? this.imageUrl,
      isStandard: isStandard ?? this.isStandard,
      userId: userId ?? this.userId,
      isFavorite: isFavorite ?? this.isFavorite,
      gifUrl: gifUrl ?? this.gifUrl,
      movementType: movementType ?? this.movementType,
      difficulty: difficulty ?? this.difficulty,
      equipmentType: equipmentType ?? this.equipmentType,
      inputMode: inputMode ?? this.inputMode,
    );
  }

  bool get isCustom => !isStandard && userId != null;

  /// Input mode: explicit DB override takes priority, else derived from
  /// category/equipment. Stable default is `weighted`, so every existing
  /// strength exercise keeps its current UI unchanged.
  ExerciseInputMode get effectiveInputMode {
    switch (inputMode) {
      case 'cardio':
        return ExerciseInputMode.cardio;
      case 'bodyweight':
        return ExerciseInputMode.bodyweight;
      case 'weighted':
        return ExerciseInputMode.weighted;
    }
    if (category == 'cardio') return ExerciseInputMode.cardio;
    if (equipmentType == 'bodyweight') return ExerciseInputMode.bodyweight;
    return ExerciseInputMode.weighted;
  }

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
      movementType: json['movement_type'] as String?,
      difficulty: json['difficulty'] as String?,
      equipmentType: json['equipment_type'] as String?,
      inputMode: json['input_mode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'name_ru': nameRu,
        'category': category,
        'description': description,
        'description_ru': descriptionRu,
        'image_url': imageUrl,
        'is_standard': isStandard,
        'is_favorite': isFavorite,
        'gif_url': gifUrl,
        'movement_type': movementType,
        'difficulty': difficulty,
        'equipment_type': equipmentType,
        'input_mode': inputMode,
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

  static String movementDisplayName(String type) {
    const map = {
      'press': 'Жим',
      'row': 'Тяга',
      'fly': 'Разводка',
      'curl': 'Сгибание',
      'extension': 'Разгибание',
      'raise': 'Подъём',
      'squat': 'Приседания',
      'lunge': 'Выпад',
      'plank': 'Планка',
      'cardio': 'Кардио',
      'other': 'Другое',
    };
    return map[type] ?? type;
  }

  static String difficultyDisplayName(String d) {
    const map = {
      'beginner': 'Начинающий',
      'intermediate': 'Средний',
      'advanced': 'Продвинутый',
    };
    return map[d] ?? d;
  }

  static String equipmentDisplayName(String? type) {
    const map = {
      'barbell': 'Штанга',
      'dumbbell': 'Гантели',
      'cable': 'Блок/кабель',
      'machine': 'Тренажёр',
      'bodyweight': 'Вес тела',
      'other': 'Другое',
    };
    return type != null ? (map[type] ?? type) : 'Другое';
  }

  /// Movement types available for a given category.
  static List<String> movementsForCategory(String categoryKey) {
    const map = {
      'chest': ['press', 'fly', 'curl'],
      'back': ['row', 'raise', 'extension'],
      'shoulders': ['press', 'raise', 'row', 'fly'],
      'arms': ['curl', 'extension', 'press'],
      'legs': ['squat', 'lunge', 'press', 'curl', 'extension', 'raise'],
      'core': ['plank', 'curl', 'raise'],
      'cardio': ['cardio'],
    };
    return map[categoryKey] ?? [];
  }

  int get difficultyOrder {
    switch (difficulty) {
      case 'beginner':
        return 0;
      case 'intermediate':
        return 1;
      case 'advanced':
        return 2;
      default:
        return 3;
    }
  }

  /// Returns movement_type from DB if set, otherwise infers from exercise name.
  /// Every exercise gets a type — no exercise falls through to 'other'.
  String get effectiveMovementType {
    if (movementType != null && movementType != 'other') return movementType!;
    final n = '${nameRu ?? ''} $name'.toLowerCase();
    bool has(List<String> words) => words.any((w) => n.contains(w));

    switch (category) {
      case 'chest':
        if (has([
          'разводк',
          'fly',
          'flye',
          'кроссов',
          'crossover',
          'бабочк',
          'pec deck',
          'pec-deck',
          'сведени',
          'кабельн'
        ])) {
          return 'fly';
        }
        // default: press (жим лёжа, отжимания, дипы и всё остальное)
        return 'press';

      case 'back':
        if (has([
          'гиперэкст',
          'hyperext',
          'разгибани',
          'good morning',
          'наклон',
          'roman chair',
          'экстензи'
        ])) {
          return 'extension';
        }
        if (has([
          'подтягив',
          'pull-up',
          'pullup',
          'chin-up',
          'chinup',
          'тяга верхн',
          'тяга к груд',
          'lat pull',
          'pulldown',
          'тяга к под',
          'верхний блок',
          'блок сверх',
          'вис',
          'мышечный выход'
        ])) {
          return 'raise';
        }
        // default: row (тяга штанги, тяга гантели, становая, всё остальное)
        return 'row';

      case 'shoulders':
        if (has([
          'задни',
          'rear',
          'обратн',
          'reverse fly',
          'face pull',
          'обратная разводк',
          'rear delt'
        ])) {
          return 'fly';
        }
        if (has([
          'тяга к подборо',
          'upright row',
          'шраг',
          'shrug',
          'высокая тяга'
        ])) {
          return 'row';
        }
        if (has([
          'жим',
          'press',
          'арнольд',
          'arnold',
          'military',
          'overhead',
          'за голов'
        ])) {
          return 'press';
        }
        // default: raise (боковые махи, подъём вперёд и всё остальное)
        return 'raise';

      case 'arms':
        if (has([
          'трицепс',
          'tricep',
          'разгибани',
          'extension',
          'pushdown',
          'skull',
          'french',
          'kickback',
          'узким',
          'close grip',
          'жим узк',
          'отжимани на брус',
          'французск'
        ])) {
          return 'extension';
        }
        if (has(['жим', 'press', 'dip', 'брус', 'отжим'])) return 'press';
        // default: curl (бицепс, молоток, концентрированное и всё остальное)
        return 'curl';

      case 'legs':
        if (has(['икр', 'calf', 'носк', 'donkey', 'gastrocn'])) return 'raise';
        if (has(['разгибани', 'leg extension', 'квадр'])) return 'extension';
        if (has([
          'сгибани',
          'leg curl',
          'hamstring',
          'nordic',
          'румынск',
          'romanian',
          'мертвая',
          'мёртвая'
        ])) {
          return 'curl';
        }
        if (has(['жим ног', 'leg press', 'гак', 'hack', 'смит', 'smith'])) {
          return 'press';
        }
        if (has([
          'выпад',
          'lunge',
          'болгарск',
          'bulgarian',
          'split squat',
          'степ',
          'step-up',
          'step up',
          'реверс выпад'
        ])) {
          return 'lunge';
        }
        // default: squat (приседания и всё остальное)
        return 'squat';

      case 'core':
        if (has([
          'планка',
          'plank',
          'ролик',
          'ab wheel',
          'dead bug',
          'вакуум',
          'vacuum',
          'hollow',
          'статик',
          'l-sit'
        ])) {
          return 'plank';
        }
        if (has([
          'подъём ног',
          'подъем ног',
          'leg raise',
          'knee raise',
          'висе',
          'hanging',
          'складк',
          'уголок'
        ])) {
          return 'raise';
        }
        // default: curl (скручивания, пресс и всё остальное)
        return 'curl';

      case 'cardio':
        return 'cardio';
    }
    return movementType ?? 'other';
  }
}
