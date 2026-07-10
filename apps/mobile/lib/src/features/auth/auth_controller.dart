import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/auth_api_client.dart';
import 'data/token_store.dart';

/// Whether the user has a session. `unknown` only appears before the first
/// read of the token store (kept for symmetry; the store is synchronous here).
enum AuthStatus { unknown, authenticated, unauthenticated }

/// Immutable auth view-state consumed by the router and the auth screens.
class AuthState {
  const AuthState({
    required this.status,
    this.isSubmitting = false,
    this.errorMessage,
  });

  final AuthStatus status;
  final bool isSubmitting;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    bool? isSubmitting,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
    );
  }
}

/// Owns the authentication lifecycle: initial session detection, login,
/// register and logout. On success the tokens are persisted and the status
/// flips to authenticated, which the router observes to redirect.
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._api, this._store)
      : super(
          AuthState(
            status: _store.hasSession
                ? AuthStatus.authenticated
                : AuthStatus.unauthenticated,
          ),
        );

  final AuthApiClient _api;
  final TokenStore _store;

  Future<bool> login(String email, String password) =>
      _submit(() => _api.login(email.trim(), password));

  Future<bool> register(String email, String password) =>
      _submit(() => _api.register(email.trim(), password));

  Future<bool> _submit(Future<AuthTokens> Function() call) async {
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      final tokens = await call();
      await _store.save(tokens);
      state = const AuthState(status: AuthStatus.authenticated);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Algo salió mal. Inténtalo de nuevo.',
      );
      return false;
    }
  }

  Future<void> logout() async {
    final refresh = _store.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await _api.logout(refresh);
    }
    await _store.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Clear any surfaced error (e.g. when the user edits the form again).
  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }
}
