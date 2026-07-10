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
  static const _kEmail = 'mindos.auth.email';

  String? get accessToken => _prefs.getString(_kAccess);
  String? get refreshToken => _prefs.getString(_kRefresh);
  String? get email => _prefs.getString(_kEmail);
  bool get hasSession => (accessToken?.isNotEmpty ?? false);

  /// A friendly display name derived from the email local part
  /// (e.g. "daniel.perez@x.com" -> "Daniel"). Null when unknown.
  String? get displayName {
    final e = email;
    if (e == null || !e.contains('@')) return null;
    final local = e.split('@').first.split(RegExp(r'[._-]')).first;
    if (local.isEmpty) return null;
    return local[0].toUpperCase() + local.substring(1).toLowerCase();
  }

  Future<void> save(AuthTokens tokens) async {
    await _prefs.setString(_kAccess, tokens.accessToken);
    await _prefs.setString(_kRefresh, tokens.refreshToken);
  }

  Future<void> saveEmail(String email) => _prefs.setString(_kEmail, email);

  Future<void> clear() async {
    await _prefs.remove(_kAccess);
    await _prefs.remove(_kRefresh);
    await _prefs.remove(_kEmail);
  }
}
