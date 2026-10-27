import '../../shared/mindos_api.dart';

/// The signed-in user's profile and preferences (mirrors `/v1/me`).
class Me {
  const Me({
    required this.id,
    required this.email,
    required this.timezone,
    required this.currency,
    required this.effectiveCurrency,
  });

  final String id;
  final String email;
  final String timezone;

  /// Null until the user (or the app's suggestion) picks one.
  final String? currency;

  /// The currency to display money in (falls back to USD server-side).
  final String effectiveCurrency;

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        id: json['id'] as String,
        email: json['email'] as String,
        timezone: (json['timezone'] as String?) ?? 'UTC',
        currency: json['currency'] as String?,
        effectiveCurrency: (json['effective_currency'] as String?) ?? 'USD',
      );
}

class MeApi {
  MeApi(this._api);
  final MindosApi _api;

  Future<Me> get() async =>
      Me.fromJson(await _api.get('/me') as Map<String, dynamic>);

  Future<Me> update({String? timezone, String? currency}) async {
    final json = await _api.patch('/me', {
      if (timezone != null) 'timezone': timezone,
      if (currency != null) 'currency': currency,
    });
    return Me.fromJson(json as Map<String, dynamic>);
  }
}
