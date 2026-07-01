import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Root widget of the mindOS mobile app.
///
/// Uses Material 3 and GoRouter. Mobile-first per ADR-010.
class MindOsApp extends ConsumerWidget {
  const MindOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'mindOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B4BE1)),
      ),
      routerConfig: router,
    );
  }
}
