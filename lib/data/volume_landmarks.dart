/// Volume Landmarks по методологии Renaissance Periodization (Israetel et al.).
///
/// Объём измеряется в **рабочих подходах на группу мышц за неделю** (без
/// разминочных и без явно warmup-помеченных сетов в БД).
///
/// Зоны:
///   • MEV (Minimum Effective Volume) — порог ниже которого нет роста,
///     только поддержание.
///   • MAV (Maximum Adaptive Volume) — диапазон с максимальным ростом,
///     задаётся парой [mavLow, mavHigh].
///   • MRV (Maximum Recoverable Volume) — потолок: дальше начинается
///     перетрен, эффект отрицательный.
///
/// Числа усреднены для **intermediate-лифтера**. Для начинающих немного
/// меньше, для продвинутых больше — но в первой итерации не дифференцируем,
/// иначе разница потребует калибровки которой у нас нет.
library;

class VolumeLandmarks {
  final int mev;
  final int mavLow;
  final int mavHigh;
  final int mrv;

  const VolumeLandmarks({
    required this.mev,
    required this.mavLow,
    required this.mavHigh,
    required this.mrv,
  });
}

enum VolumeZone {
  /// Меньше MEV — недогружаешь, мышца не растёт.
  underMev,

  /// Между MEV и MAV-low — стимул есть, но не оптимальный.
  belowOptimal,

  /// В диапазоне MAV — оптимальный объём для роста.
  optimal,

  /// Между MAV-high и MRV — перегруз, риск перетрена.
  aboveOptimal,

  /// Больше MRV — точно перетрен, нужен deload.
  overMrv,
}

/// Display-friendly короткое название зоны.
String volumeZoneLabel(VolumeZone z) {
  switch (z) {
    case VolumeZone.underMev:
      return 'Мало';
    case VolumeZone.belowOptimal:
      return 'Ниже нормы';
    case VolumeZone.optimal:
      return 'Оптимум';
    case VolumeZone.aboveOptimal:
      return 'Выше нормы';
    case VolumeZone.overMrv:
      return 'Перегруз';
  }
}

/// Длинная подсказка для тултипа.
String volumeZoneAdvice(VolumeZone z) {
  switch (z) {
    case VolumeZone.underMev:
      return 'Слишком мало для роста. Добавь 2-4 подхода в неделю.';
    case VolumeZone.belowOptimal:
      return 'Стимул есть, но мышца может расти быстрее. Добавь пару подходов.';
    case VolumeZone.optimal:
      return 'Оптимальный объём — здесь рост максимальный. Продолжай.';
    case VolumeZone.aboveOptimal:
      return 'Близко к потолку восстановления. Следи за самочувствием.';
    case VolumeZone.overMrv:
      return 'Перебор. Снизь объём или сделай неделю deload.';
  }
}

/// Категория мышц (наши `exercises.category`) → её landmarks.
/// Кардио намеренно отсутствует — концепция не применима.
const Map<String, VolumeLandmarks> kMuscleVolumeLandmarks = {
  'chest':     VolumeLandmarks(mev: 10, mavLow: 12, mavHigh: 18, mrv: 22),
  'back':      VolumeLandmarks(mev: 10, mavLow: 14, mavHigh: 22, mrv: 25),
  'shoulders': VolumeLandmarks(mev:  8, mavLow: 12, mavHigh: 20, mrv: 26),
  'arms':      VolumeLandmarks(mev:  8, mavLow: 12, mavHigh: 18, mrv: 22),
  'legs':      VolumeLandmarks(mev: 10, mavLow: 14, mavHigh: 20, mrv: 24),
  'core':      VolumeLandmarks(mev:  6, mavLow: 12, mavHigh: 20, mrv: 25),
};

/// Определяет в какую зону попадает [sets] для заданных [landmarks].
VolumeZone zoneFor(int sets, VolumeLandmarks landmarks) {
  if (sets < landmarks.mev) return VolumeZone.underMev;
  if (sets < landmarks.mavLow) return VolumeZone.belowOptimal;
  if (sets <= landmarks.mavHigh) return VolumeZone.optimal;
  if (sets <= landmarks.mrv) return VolumeZone.aboveOptimal;
  return VolumeZone.overMrv;
}

/// Снимок объёма для одной группы мышц.
class MuscleVolumeStatus {
  final String category;          // 'chest', 'back', etc.
  final int weeklySets;
  final VolumeLandmarks landmarks;
  final VolumeZone zone;

  const MuscleVolumeStatus({
    required this.category,
    required this.weeklySets,
    required this.landmarks,
    required this.zone,
  });
}
