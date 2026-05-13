import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/screens/exercises/create_exercise_screen.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/image_cache_manager.dart';

/// Category chip data: DB key → display name.
const _categoryChips = [
  ('chest', 'Грудь'),
  ('back', 'Спина'),
  ('shoulders', 'Плечи'),
  ('arms', 'Руки'),
  ('legs', 'Ноги'),
  ('core', 'Пресс'),
  ('cardio', 'Кардио'),
];

const _categoryOrder = [
  'Грудь',
  'Спина',
  'Плечи',
  'Руки',
  'Ноги',
  'Пресс',
  'Кардио'
];

class ExerciseCatalogScreen extends StatefulWidget {
  const ExerciseCatalogScreen({super.key});

  @override
  State<ExerciseCatalogScreen> createState() => _ExerciseCatalogScreenState();
}

class _ExerciseCatalogScreenState extends State<ExerciseCatalogScreen> {
  static const _loadTimeout = Duration(seconds: 8);

  List<Exercise> _allExercises = [];
  bool _loading = true;
  String _searchQuery = '';
  String? _selectedCategoryKey;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final cached = await ExerciseService.getCachedExercises();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _allExercises = cached;
        _loading = false;
      });
    }

    try {
      final exercises =
          await ExerciseService.getExercises().timeout(_loadTimeout);
      if (!mounted) return;
      setState(() {
        _allExercises = exercises;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      final hadVisibleData = _allExercises.isNotEmpty;
      final fallback = hadVisibleData
          ? _allExercises
          : ExerciseService.getLocalFallbackExercises();
      setState(() {
        _allExercises = fallback;
        _loading = false;
      });
      if (fallback.isEmpty || hadVisibleData) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Каталог открыт из локального кеша'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
    });
  }

  List<Exercise> get _filtered {
    var list = _allExercises;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              (e.nameRu?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (_selectedCategoryKey != null) {
      list = list.where((e) => e.category == _selectedCategoryKey).toList();
    }
    list.sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  /// Group exercises by category display name, respecting order.
  Map<String, List<Exercise>> get _grouped {
    final map = <String, List<Exercise>>{};
    for (final ex in _filtered) {
      final cat = Exercise.categoryDisplayName(ex.category);
      (map[cat] ??= []).add(ex);
    }
    // Sort keys by _categoryOrder
    final sorted = <String, List<Exercise>>{};
    for (final c in _categoryOrder) {
      if (map.containsKey(c)) sorted[c] = map[c]!;
    }
    // Add any remaining categories not in order
    for (final entry in map.entries) {
      if (!sorted.containsKey(entry.key)) sorted[entry.key] = entry.value;
    }
    return sorted;
  }

  void _showExerciseDetail(Exercise ex) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (ctx, scrollController) => _ExerciseDetailSheet(
          exercise: ex,
          scrollController: scrollController,
          onLoaded: _replaceExercise,
        ),
      ),
    );
  }

  void _replaceExercise(Exercise updated) {
    if (!mounted) return;
    setState(() {
      final idx = _allExercises.indexWhere((e) => e.id == updated.id);
      if (idx != -1) _allExercises[idx] = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Упражнения'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Column(
              children: [
                // Search
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Поиск упражнения...',
                      hintStyle:
                          const TextStyle(color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                // Category chips
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _chip(null, 'Все'),
                      ..._categoryChips.map((c) => _chip(c.$1, c.$2)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Exercise list
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'Ничего не найдено',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : _selectedCategoryKey != null
                          ? _buildFlatList()
                          : _buildGroupedList(),
                ),
              ],
            ),
    );
  }

  Widget _chip(String? key, String label) {
    final selected = _selectedCategoryKey == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() =>
            _selectedCategoryKey = _selectedCategoryKey == key ? null : key),
        selectedColor: AppColors.accent.withValues(alpha: 0.2),
        checkmarkColor: AppColors.accent,
        labelStyle: TextStyle(
          color: selected ? AppColors.accent : AppColors.textSecondary,
          fontSize: 13,
        ),
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildFlatList() {
    final exercises = _filtered;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: exercises.length,
      itemBuilder: (_, i) => _exerciseTile(exercises[i]),
    );
  }

  Widget _buildGroupedList() {
    final groups = _grouped;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: groups.length,
      itemBuilder: (_, i) {
        final category = groups.keys.elementAt(i);
        final exercises = groups[category]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Row(
                children: [
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${exercises.length}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            ...exercises.map(_exerciseTile),
          ],
        );
      },
    );
  }

  Widget _exerciseTile(Exercise ex) {
    final tile = Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        onTap: () => _showExerciseDetail(ex),
        leading: Icon(
          ex.category == 'cardio' ? Icons.directions_run : Icons.fitness_center,
          color: AppColors.accent,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(ex.displayName,
                  style: const TextStyle(color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ),
            if (ex.isCustom) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Моё',
                    style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          Exercise.categoryDisplayName(ex.category),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: ex.gifUrl != null
            ? const Icon(Icons.play_circle_outline,
                color: AppColors.textSecondary, size: 20)
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    // Standard exercises are read-only — no swipe actions.
    if (!ex.isCustom) {
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: tile);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('ex_${ex.id}'),
        direction: DismissDirection.horizontal,
        background: _swipeBg(
          color: AppColors.accent,
          icon: Icons.edit_outlined,
          label: 'Изменить',
          alignment: Alignment.centerLeft,
        ),
        secondaryBackground: _swipeBg(
          color: AppColors.error,
          icon: Icons.delete_outline,
          label: 'Удалить',
          alignment: Alignment.centerRight,
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            // Edit — open screen, keep item in list regardless of outcome.
            await _editExercise(ex);
            return false;
          }
          // endToStart — destructive. Confirm, then allow real dismissal.
          return _confirmAndDelete(ex);
        },
        child: tile,
      ),
    );
  }

  Widget _swipeBg({
    required Color color,
    required IconData icon,
    required String label,
    required Alignment alignment,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _editExercise(Exercise ex) async {
    final updated = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => CreateExerciseScreen(existing: ex)),
    );
    if (updated == null || !mounted) return;
    setState(() {
      final idx = _allExercises.indexWhere((e) => e.id == updated.id);
      if (idx != -1) _allExercises[idx] = updated;
    });
  }

  Future<bool> _confirmAndDelete(Exercise ex) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить упражнение?'),
        content: Text(
          '"${ex.displayName}" будет удалено безвозвратно. '
          'Также оно исчезнет из всех программ, где используется.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      await ExerciseService.deleteExercise(ex.id);
      if (mounted) {
        setState(() => _allExercises.removeWhere((e) => e.id == ex.id));
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось удалить упражнение')),
        );
      }
      return false;
    }
  }
}

class _ExerciseDetailSheet extends StatefulWidget {
  final Exercise exercise;
  final ScrollController scrollController;
  final ValueChanged<Exercise> onLoaded;

  const _ExerciseDetailSheet({
    required this.exercise,
    required this.scrollController,
    required this.onLoaded,
  });

  @override
  State<_ExerciseDetailSheet> createState() => _ExerciseDetailSheetState();
}

class _ExerciseDetailSheetState extends State<_ExerciseDetailSheet> {
  static const _detailTimeout = Duration(seconds: 8);

  late Exercise _exercise = widget.exercise;
  bool _loadingDetails = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    if (ExerciseService.isLocalFallbackExercise(widget.exercise)) return;
    setState(() => _loadingDetails = true);
    try {
      final detail = await ExerciseService.getExercise(
        widget.exercise.id,
        includeDetails: true,
      ).timeout(_detailTimeout);
      if (!mounted || detail == null) return;
      setState(() => _exercise = detail);
      widget.onLoaded(detail);
    } catch (_) {
      // Keep the lightweight exercise data visible. Details are optional here.
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaUrls = _exercise.mediaUrls;
    final description = _exercise.descriptionRu ?? _exercise.description;

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _exercise.displayName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  Exercise.categoryDisplayName(_exercise.category),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_exercise.equipmentType != null) ...[
                const SizedBox(width: 8),
                Text(
                  _exercise.equipmentType!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          if (mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ExerciseMedia(urls: mediaUrls),
          ],
          if (_loadingDetails) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator.adaptive()),
          ] else if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ] else if (mediaUrls.isEmpty) ...[
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Описание пока не добавлено',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExerciseMedia extends StatefulWidget {
  final List<String> urls;

  const _ExerciseMedia({required this.urls});

  @override
  State<_ExerciseMedia> createState() => _ExerciseMediaState();
}

class _ExerciseMediaState extends State<_ExerciseMedia> {
  static const _height = 260.0;

  int _index = 0;
  int _retrySeed = 0;

  @override
  void didUpdateWidget(covariant _ExerciseMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') == widget.urls.join('|')) return;
    _index = 0;
    _retrySeed = 0;
  }

  void _retry() {
    setState(() {
      _index = 0;
      _retrySeed += 1;
    });
  }

  void _tryNextUrl() {
    if (_index + 1 >= widget.urls.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _index + 1 >= widget.urls.length) return;
      setState(() => _index += 1);
    });
  }

  Widget _box({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        height: _height,
        color: AppColors.surface,
        child: Center(child: child),
      ),
    );
  }

  Widget _fallback() {
    return _box(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 34,
            color: AppColors.textSecondary.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 10),
          const Text(
            'Картинка не загрузилась',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  Widget _loadingBox() {
    return _box(
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator.adaptive(),
          ),
          SizedBox(height: 12),
          Text(
            'Загружаем картинку...',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return _fallback();
    final url = widget.urls[_index].trim().replaceAll(' ', '%20');

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        key: ValueKey('$url:$_retrySeed'),
        cacheManager: AppImageCacheManager.instance,
        imageUrl: url,
        width: double.infinity,
        height: _height,
        fit: BoxFit.contain,
        placeholder: (_, __) => _loadingBox(),
        errorWidget: (_, __, ___) {
          _tryNextUrl();
          return _index + 1 < widget.urls.length ? _loadingBox() : _fallback();
        },
      ),
    );
  }
}
