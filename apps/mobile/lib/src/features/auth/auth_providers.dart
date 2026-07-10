import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_controller.dart';
import 'data/auth_api_client.dart';
import 'data/token_store.dart';

/// Provides the initialized [SharedPreferences] instance.
///
/// Overridden in `main()` with the real instance obtained during startup, so
/// the token store (and therefore the initial auth status) is available
/// synchronously when the router first builds.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main().',
  );
});

/// Persistent token storage.
final tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore(ref.watch(sharedPreferencesProvider));
});

/// HTTP client for the auth endpoints.
final authApiClientProvider = Provider<AuthApiClient>((ref) {
  return AuthApiClient();
});

/// The authentication controller / state.
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(authApiClientProvider),
    ref.watch(tokenStoreProvider),
  );
});
