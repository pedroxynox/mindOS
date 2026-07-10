import 'package:shared_preferences/shared_preferences.dart';

import 'auth_api_client.dart';

/// Persists the auth session (access + refresh tokens) across app restarts.
///
/// Uses [SharedPreferences] so a single API covers web (localStorage) and
/// mobile (native prefs). Tokens are opaque strings; the access token is short
/// lived and the refresh token is single-use/rotating on the server side.
class TokenStore {
  TokenStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kAccess = 'mindos.auth.access';
  static const _kRefresh = 'mindos.auth.refresh';

  String? get accessToken => _prefs.getString(_kAccess);
  String? get refreshToken => _prefs.getString(_kRefresh);
  bool get hasSession => (accessToken?.isNotEmpty ?? false);

  Future<void> save(AuthTokens tokens) async {
    await _prefs.setString(_kAccess, tokens.accessToken);
    await _prefs.setString(_kRefresh, tokens.refreshToken);
  }

  Future<void> clear() async {
    await _prefs.remove(_kAccess);
    await _prefs.remove(_kRefresh);
  }
}
