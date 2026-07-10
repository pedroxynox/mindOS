import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/features/auth/auth_providers.dart';

Future<void> main() async {
  // Required before awaiting plugins (SharedPreferences) during startup.
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted session once at startup so the router knows synchronously
  // whether the user is signed in.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MindOsApp(),
    ),
  );
}
