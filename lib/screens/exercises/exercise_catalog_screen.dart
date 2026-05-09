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
    try {
      final exercises =
          await ExerciseService.getExercises(includeDetails: true);
      if (!mounted) return;
      setState(() {
        _allExercises = exercises;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
    final gifUrl = ex.gifUrl;
    final description = ex.descriptionRu ?? ex.description;

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
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
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
                ex.displayName,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      Exercise.categoryDisplayName(ex.category),
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (ex.equipmentType != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      ex.equipmentType!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ],
              ),
              if (gifUrl != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    cacheManager: AppImageCacheManager.instance,
                    imageUrl: gifUrl,
                    width: double.infinity,
                    height: 260,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const SizedBox(
                      height: 260,
                      child:
                          Center(child: CircularProgressIndicator.adaptive()),
                    ),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              if (gifUrl == null &&
                  (description == null || description.isEmpty)) ...[
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Описание пока не добавлено',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
