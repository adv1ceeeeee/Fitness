/// Стандартные программы тренировок.
///
/// Два формата:
///   • Одна тренировка:  обязательные ключи `name`, `days`, `exercises`.
///   • Мульти-секция:    обязательный ключ `name` + `sections` — список
///     объектов с ключами `name`, `days`, `exercises`.
///
/// `exercises` содержат: `name` (поиск по contains), `sets`, `reps`, `rest`.
/// `goal`    — 'general' | 'weight_loss' | 'mass_gain' | 'strength' | 'endurance'
/// `level`   — 'beginner' | 'intermediate' | 'advanced'
/// `premium` — true: продвинутая программа (зарезервировано для монетизации).
///
/// Матрица рекомендаций (используется в онбординге):
///   goal\level    beginner              intermediate          advanced
///   general       Новичок (Full body)   Верх/Низ (Upper-Lower) PPL (Толчок/Тяга/Ноги)
///   weight_loss   Для похудения (Круговая) Сушка (Рельеф)    Сушка (Рельеф)
///   mass_gain     Набор массы (Сплит)   PPL (Толчок/Тяга/Ноги) PPL (Толчок/Тяга/Ноги)
///   strength      Силовая (5x5)         Силовая (5x5)         Пауэрлифтинг (Сила)
///   endurance     Выносливость (Кардио) Функциональный (HIIT) Функциональный (HIIT)
library;

const List<Map<String, dynamic>> standardPrograms = [

  // ── НАЧИНАЮЩИЕ ───────────────────────────────────────────────────────────

  {
    'name': 'Новичок (Full body)',
    'goal': 'general',
    'level': 'beginner',
    'days': [1, 3, 5], // Пн, Ср, Пт
    'exercises': [
      {'name': 'Приседания со штангой', 'sets': 3, 'reps': '8-12', 'rest': 90},
      {'name': 'Жим лежа',              'sets': 3, 'reps': '8-12', 'rest': 90},
      {'name': 'Тяга верхнего блока',   'sets': 3, 'reps': '8-12', 'rest': 90},
      {'name': 'Жим гантелей сидя',     'sets': 3, 'reps': '8-12', 'rest': 90},
      {'name': 'Подъем штанги на бицепс','sets':3, 'reps': '8-12', 'rest': 90},
    ],
  },

  {
    'name': 'Для похудения (Круговая)',
    'goal': 'weight_loss',
    'level': 'beginner',
    'days': [1, 2, 4, 5],
    'exercises': [
      {'name': 'Приседания со штангой', 'sets': 3, 'reps': '15', 'rest': 60},
      {'name': 'Жим лежа',              'sets': 3, 'reps': '15', 'rest': 60},
      {'name': 'Тяга верхнего блока',   'sets': 3, 'reps': '15', 'rest': 60},
      {'name': 'Берпи',                 'sets': 3, 'reps': '10', 'rest': 45},
      {'name': 'Беговая дорожка',       'sets': 1, 'reps': '15 мин', 'rest': 0},
    ],
  },

  {
    'name': 'Набор массы (Сплит)',
    'goal': 'mass_gain',
    'level': 'beginner',
    'days': [1, 2, 4, 5],
    'exercises': [
      {'name': 'Жим лежа',              'sets': 4, 'reps': '8-12', 'rest': 90},
      {'name': 'Французский жим',       'sets': 3, 'reps': '8-12', 'rest': 90},
      {'name': 'Тяга верхнего блока',   'sets': 4, 'reps': '8-12', 'rest': 90},
      {'name': 'Подъем штанги на бицепс','sets':3, 'reps': '8-12', 'rest': 90},
      {'name': 'Приседания со штангой', 'sets': 4, 'reps': '8-12', 'rest': 90},
      {'name': 'Жим гантелей сидя',     'sets': 3, 'reps': '8-12', 'rest': 90},
    ],
  },

  {
    'name': 'Силовая (5x5)',
    'goal': 'strength',
    'level': 'beginner',
    'days': [1, 3, 5],
    'exercises': [
      {'name': 'Приседания со штангой', 'sets': 5, 'reps': '5', 'rest': 120},
      {'name': 'Жим лежа',              'sets': 5, 'reps': '5', 'rest': 120},
      {'name': 'Становая тяга',         'sets': 1, 'reps': '5', 'rest': 120},
    ],
  },

  {
    'name': 'Выносливость (Кардио)',
    'goal': 'endurance',
    'level': 'beginner',
    'days': [1, 3, 5],
    'exercises': [
      {'name': 'Беговая дорожка',       'sets': 1, 'reps': '20 мин', 'rest': 0},
      {'name': 'Велосипед',             'sets': 1, 'reps': '15 мин', 'rest': 0},
      {'name': 'Гребной тренажёр',      'sets': 1, 'reps': '10 мин', 'rest': 0},
      {'name': 'Джампинг-джек',         'sets': 3, 'reps': '40',    'rest': 30},
      {'name': 'Прыжки со скакалкой',   'sets': 3, 'reps': '2 мин', 'rest': 60},
      {'name': 'Альпинист',             'sets': 3, 'reps': '30',    'rest': 30},
      {'name': 'Берпи',                 'sets': 3, 'reps': '10',    'rest': 45},
      {'name': 'Планка на локтях',      'sets': 3, 'reps': '45 сек','rest': 30},
    ],
  },

  {
    'name': 'Домашние тренировки',
    'goal': 'general',
    'level': 'beginner',
    'days': [1, 3, 5],
    'exercises': [
      {'name': 'Отжимания',                     'sets': 4, 'reps': '15',    'rest': 60},
      {'name': 'Австралийские подтягивания',    'sets': 3, 'reps': '12',    'rest': 60},
      {'name': 'Воздушные приседания',          'sets': 3, 'reps': '20',    'rest': 60},
      {'name': 'Выпады на месте',               'sets': 3, 'reps': '12',    'rest': 60},
      {'name': 'Ягодичный мостик',              'sets': 4, 'reps': '20',    'rest': 45},
      {'name': 'Планка на локтях',              'sets': 3, 'reps': '45 сек','rest': 45},
      {'name': 'Скручивания лёжа',              'sets': 3, 'reps': '20',    'rest': 45},
      {'name': 'Берпи',                         'sets': 3, 'reps': '10',    'rest': 60},
      {'name': 'Альпинист',                     'sets': 3, 'reps': '30',    'rest': 45},
      {'name': 'Джампинг-джек',                 'sets': 3, 'reps': '30',    'rest': 30},
    ],
  },

  {
    'name': 'Ягодицы и ноги',
    'goal': 'general',
    'level': 'beginner',
    'days': [1, 3, 5],
    'exercises': [
      {'name': 'Ягодичный мостик со штангой',      'sets': 4, 'reps': '15',    'rest': 75},
      {'name': 'Приседания со штангой',            'sets': 4, 'reps': '12',    'rest': 90},
      {'name': 'Жим ногами с высокой постановкой', 'sets': 4, 'reps': '15',    'rest': 75},
      {'name': 'Болгарские приседания',            'sets': 3, 'reps': '12',    'rest': 75},
      {'name': 'Разгибания ног в тренажёре',       'sets': 3, 'reps': '15',    'rest': 60},
      {'name': 'Сгибания ног в тренажёре',         'sets': 3, 'reps': '15',    'rest': 60},
      {'name': 'Отведение ног на блоке',           'sets': 4, 'reps': '20',    'rest': 45},
      {'name': 'Разведение ног в тренажёре',       'sets': 3, 'reps': '20',    'rest': 45},
      {'name': 'Подъём на носки стоя',             'sets': 4, 'reps': '25',    'rest': 45},
    ],
  },

  {
    'name': 'Кор и пресс',
    'goal': 'general',
    'level': 'beginner',
    'days': [1, 3, 5],
    'exercises': [
      {'name': 'Планка',                       'sets': 4, 'reps': '60 сек', 'rest': 45},
      {'name': 'Скручивания лёжа',             'sets': 4, 'reps': '20',    'rest': 45},
      {'name': 'Обратные скручивания',         'sets': 3, 'reps': '15',    'rest': 45},
      {'name': 'Велосипед (пресс)',            'sets': 3, 'reps': '20',    'rest': 45},
      {'name': 'Подъём ног в висе',            'sets': 3, 'reps': '15',    'rest': 60},
      {'name': 'Русский твист',                'sets': 3, 'reps': '20',    'rest': 45},
      {'name': 'Боковая планка',               'sets': 3, 'reps': '45 сек','rest': 30},
      {'name': 'Колесо пресса',                'sets': 3, 'reps': '15',    'rest': 60},
      {'name': 'Дровосек на блоке',            'sets': 3, 'reps': '15',    'rest': 45},
      {'name': 'Альпинист',                    'sets': 3, 'reps': '30',    'rest': 30},
    ],
  },

  // ── СРЕДНИЙ УРОВЕНЬ ──────────────────────────────────────────────────────

  {
    'name': 'PPL (Толчок / Тяга / Ноги)',
    'goal': 'mass_gain',
    'level': 'intermediate',
    'premium': true,
    'sections': [
      {
        'name': 'PPL — Толчок',
        'days': [1, 4], // Пн + Чт
        'exercises': [
          {'name': 'Жим лежа',                       'sets': 4, 'reps': '8-12',  'rest': 90},
          {'name': 'Жим штанги на наклонной скамье', 'sets': 3, 'reps': '10-12', 'rest': 90},
          {'name': 'Жим гантелей лёжа',              'sets': 3, 'reps': '10-12', 'rest': 75},
          {'name': 'Жим гантелей сидя',              'sets': 3, 'reps': '10-12', 'rest': 75},
          {'name': 'Махи гантелями в стороны',       'sets': 3, 'reps': '15',    'rest': 60},
          {'name': 'Разгибания на блоке (трицепс)',  'sets': 3, 'reps': '12-15', 'rest': 60},
          {'name': 'Французский жим лёжа',           'sets': 3, 'reps': '10-12', 'rest': 60},
        ],
      },
      {
        'name': 'PPL — Тяга',
        'days': [2, 5], // Вт + Пт
        'exercises': [
          {'name': 'Подтягивания',                   'sets': 4, 'reps': '8-10',  'rest': 90},
          {'name': 'Тяга штанги в наклоне',          'sets': 4, 'reps': '8-10',  'rest': 90},
          {'name': 'Тяга нижнего блока сидя',        'sets': 3, 'reps': '10-12', 'rest': 75},
          {'name': 'Тяга гантели в наклоне',         'sets': 3, 'reps': '10-12', 'rest': 75},
          {'name': 'Тяга верхнего блока',            'sets': 3, 'reps': '10-12', 'rest': 75},
          {'name': 'Подъем штанги на бицепс',        'sets': 3, 'reps': '10-12', 'rest': 60},
          {'name': 'Молотковые сгибания',            'sets': 3, 'reps': '12-15', 'rest': 60},
        ],
      },
      {
        'name': 'PPL — Ноги',
        'days': [3, 6], // Ср + Сб
        'exercises': [
          {'name': 'Приседания со штангой',          'sets': 4, 'reps': '8-12',  'rest': 120},
          {'name': 'Жим ногами',                     'sets': 4, 'reps': '10-12', 'rest': 90},
          {'name': 'Разгибания ног в тренажёре',     'sets': 3, 'reps': '12-15', 'rest': 60},
          {'name': 'Сгибания ног в тренажёре',       'sets': 3, 'reps': '12-15', 'rest': 60},
          {'name': 'Румынская тяга',                 'sets': 3, 'reps': '10-12', 'rest': 90},
          {'name': 'Подъём на носки стоя',           'sets': 4, 'reps': '20',    'rest': 45},
        ],
      },
    ],
  },

  {
    'name': 'Верх / Низ (Upper-Lower)',
    'goal': 'general',
    'level': 'intermediate',
    'premium': true,
    'sections': [
      {
        'name': 'Верх тела',
        'days': [1, 4], // Пн + Чт
        'exercises': [
          {'name': 'Жим лежа',                       'sets': 4, 'reps': '8-10',  'rest': 90},
          {'name': 'Жим штанги на наклонной скамье', 'sets': 3, 'reps': '10-12', 'rest': 90},
          {'name': 'Тяга верхнего блока',            'sets': 4, 'reps': '10-12', 'rest': 90},
          {'name': 'Тяга нижнего блока сидя',        'sets': 3, 'reps': '10-12', 'rest': 75},
          {'name': 'Жим гантелей сидя',              'sets': 3, 'reps': '10-12', 'rest': 75},
          {'name': 'Подъем штанги на бицепс',        'sets': 3, 'reps': '10-12', 'rest': 60},
          {'name': 'Разгибания на блоке (трицепс)',  'sets': 3, 'reps': '12-15', 'rest': 60},
        ],
      },
      {
        'name': 'Низ тела',
        'days': [2, 5], // Вт + Пт
        'exercises': [
          {'name': 'Приседания со штангой',          'sets': 4, 'reps': '8-12',  'rest': 120},
          {'name': 'Жим ногами',                     'sets': 4, 'reps': '10-15', 'rest': 90},
          {'name': 'Разгибания ног в тренажёре',     'sets': 3, 'reps': '12-15', 'rest': 60},
          {'name': 'Сгибания ног в тренажёре',       'sets': 3, 'reps': '12-15', 'rest': 60},
          {'name': 'Румынская тяга',                 'sets': 3, 'reps': '10-12', 'rest': 90},
          {'name': 'Подъём на носки стоя',           'sets': 4, 'reps': '20',    'rest': 45},
        ],
      },
    ],
  },

  {
    'name': 'Сушка (Рельеф)',
    'goal': 'weight_loss',
    'level': 'intermediate',
    'premium': true,
    'days': [1, 2, 3, 4, 5],
    'exercises': [
      {'name': 'Жим лежа',                      'sets': 4, 'reps': '12-15', 'rest': 60},
      {'name': 'Тяга верхнего блока',           'sets': 4, 'reps': '12-15', 'rest': 60},
      {'name': 'Приседания со штангой',         'sets': 4, 'reps': '15',    'rest': 60},
      {'name': 'Жим гантелей сидя',             'sets': 3, 'reps': '15',    'rest': 45},
      {'name': 'Подъем штанги на бицепс',       'sets': 3, 'reps': '15',    'rest': 45},
      {'name': 'Французский жим лёжа',          'sets': 3, 'reps': '15',    'rest': 45},
      {'name': 'Берпи',                         'sets': 3, 'reps': '15',    'rest': 30},
      {'name': 'HIIT (интервальный бег)',        'sets': 1, 'reps': '20 мин','rest': 0},
    ],
  },

  {
    'name': 'Функциональный тренинг (HIIT)',
    'goal': 'endurance',
    'level': 'intermediate',
    'premium': true,
    'days': [1, 2, 4, 5],
    'exercises': [
      {'name': 'Берпи',                        'sets': 4, 'reps': '10',    'rest': 45},
      {'name': 'Джампинг-джек',               'sets': 3, 'reps': '30',    'rest': 30},
      {'name': 'Альпинист',                   'sets': 3, 'reps': '30',    'rest': 30},
      {'name': 'Прыжки на тумбу (Box Jump)',  'sets': 3, 'reps': '10',    'rest': 60},
      {'name': 'Приседания со штангой',       'sets': 3, 'reps': '15',    'rest': 60},
      {'name': 'Выпады с гантелями',          'sets': 3, 'reps': '12',    'rest': 60},
      {'name': 'Отжимания',                   'sets': 3, 'reps': '15',    'rest': 45},
      {'name': 'Тяга гири (свинг)',           'sets': 3, 'reps': '20',    'rest': 45},
      {'name': 'Планка',                      'sets': 3, 'reps': '45 сек','rest': 30},
    ],
  },

  // ── ПРОДВИНУТЫЙ УРОВЕНЬ ──────────────────────────────────────────────────

  {
    'name': 'Пауэрлифтинг (Сила)',
    'goal': 'strength',
    'level': 'advanced',
    'premium': true,
    'days': [1, 3, 5],
    'exercises': [
      {'name': 'Приседания со штангой',        'sets': 5, 'reps': '3-5',   'rest': 180},
      {'name': 'Жим лежа',                     'sets': 5, 'reps': '3-5',   'rest': 180},
      {'name': 'Становая тяга',                'sets': 3, 'reps': '3',     'rest': 180},
      {'name': 'Жим штанги стоя (военный жим)','sets': 3, 'reps': '5',     'rest': 120},
      {'name': 'Тяга штанги в наклоне',        'sets': 4, 'reps': '5',     'rest': 120},
      {'name': 'Жим узким хватом',             'sets': 3, 'reps': '5',     'rest': 120},
      {'name': 'Гиперэкстензия',               'sets': 3, 'reps': '10',    'rest': 90},
    ],
  },

  {
    'name': 'Недельный челлендж',
    'goal': 'general',
    'level': 'beginner',
    'premium': true,
    'days': [1, 2, 3, 4, 5],
    'exercises': [
      {'name': 'Приседания со штангой',        'sets': 3, 'reps': '15',    'rest': 60},
      {'name': 'Жим лежа',                     'sets': 3, 'reps': '15',    'rest': 60},
      {'name': 'Тяга верхнего блока',          'sets': 3, 'reps': '15',    'rest': 60},
      {'name': 'Отжимания',                    'sets': 3, 'reps': '20',    'rest': 45},
      {'name': 'Берпи',                        'sets': 3, 'reps': '10',    'rest': 45},
      {'name': 'Планка',                       'sets': 3, 'reps': '45 сек','rest': 30},
    ],
  },
];

/// All workout/section names that belong to premium programs.
final Set<String> premiumWorkoutNames = {
  for (final p in standardPrograms)
    if (p['premium'] == true) ...[
      p['name'] as String,
      if (p['sections'] != null)
        for (final s in p['sections'] as List) (s as Map)['name'] as String,
    ],
};

/// All workout/section names from ANY standard program (free + premium).
/// If a workout name is NOT in this set → it was created by the user.
final Set<String> allStandardWorkoutNames = {
  for (final p in standardPrograms) ...[
    p['name'] as String,
    if (p['sections'] != null)
      for (final s in p['sections'] as List) (s as Map)['name'] as String,
  ],
};

/// Возвращает название рекомендуемой программы по цели и уровню пользователя.
/// Используется в онбординге.
String recommendedProgramName({
  required String? goal,
  required String level, // 'beginner' | 'intermediate' | 'advanced'
}) {
  switch (goal) {
    case 'weight_loss':
      return level == 'beginner'
          ? 'Для похудения (Круговая)'
          : 'Сушка (Рельеф)';
    case 'mass_gain':
      return level == 'beginner'
          ? 'Набор массы (Сплит)'
          : 'PPL (Толчок / Тяга / Ноги)';
    case 'strength':
      return level == 'advanced'
          ? 'Пауэрлифтинг (Сила)'
          : 'Силовая (5x5)';
    case 'endurance':
      return level == 'beginner'
          ? 'Выносливость (Кардио)'
          : 'Функциональный тренинг (HIIT)';
    default: // 'general' / maintain / null
      switch (level) {
        case 'advanced':
          return 'PPL (Толчок / Тяга / Ноги)';
        case 'intermediate':
          return 'Верх / Низ (Upper-Lower)';
        default:
          return 'Новичок (Full body)';
      }
  }
}
