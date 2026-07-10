import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/api_providers.dart';
import 'data/growth_api.dart';
import 'data/growth_models.dart';

final growthApiProvider = Provider<GrowthApi>((ref) {
  return GrowthApi(ref.watch(mindosApiProvider));
});

final goalsProvider = FutureProvider.autoDispose<List<Goal>>((ref) {
  return ref.watch(growthApiProvider).listGoals();
});

final habitsProvider = FutureProvider.autoDispose<List<Habit>>((ref) {
  return ref.watch(growthApiProvider).listHabits();
});

final reflectionsProvider = FutureProvider.autoDispose<List<Reflection>>((ref) {
  return ref.watch(growthApiProvider).listReflections();
});
