import 'auth_api_client.dart';
import 'token_store.dart';

/// Source of the current access token plus a way to renew it. Every
/// authenticated client depends on this (not on the token store directly), so
/// an expired access token is refreshed transparently instead of surfacing
/// "tu sesión expiró" every hour.
abstract class TokenSource {
  /// The current access token, or null when signed out.
  String? get accessToken;

  /// Renew the session. Returns true when a fresh access token is available.
  /// Concurrent callers share ONE in-flight refresh (the refresh token is
  /// single-use on the server, so two parallel refreshes would trip the reuse
  /// detection and revoke the whole session).
  Future<bool> refresh();
}

/// Production [TokenSource] backed by the persisted [TokenStore] and the auth
/// API. When the server rejects the refresh token (expired / revoked / reused)
/// the session is over and [onExpired] is invoked so the app can sign out.
class AuthSession implements TokenSource {
  AuthSession({
    required TokenStore store,
    required AuthApiClient api,
    required void Function() onExpired,
  })  : _store = store,
        _api = api,
        _onExpired = onExpired;

  final TokenStore _store;
  final AuthApiClient _api;
  final void Function() _onExpired;

  Future<bool>? _inFlight;

  @override
  String? get accessToken => _store.accessToken;

  @override
  Future<bool> refresh() => _inFlight ??= _doRefresh().whenComplete(() {
        _inFlight = null;
      });

  Future<bool> _doRefresh() async {
    final refreshToken = _store.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      _onExpired();
      return false;
    }
    try {
      final tokens = await _api.refresh(refreshToken);
      await _store.save(tokens);
      return true;
    } on AuthException catch (e) {
      // A definitive rejection ends the session; a network failure does not.
      if (e.statusCode != null) _onExpired();
      return false;
    }
  }
}
