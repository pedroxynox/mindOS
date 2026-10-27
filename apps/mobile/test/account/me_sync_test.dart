import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/account/account_providers.dart';
import 'package:mindos/src/features/account/data/me_api.dart';
import 'package:mindos/src/features/auth/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// In-memory /v1/me that records what the app sends.
class _FakeMeApi extends MeApi {
  _FakeMeApi(this.me) : super(offlineApi());
  Me me;
  final List<Map<String, String?>> patches = [];

  @override
  Future<Me> get() async => me;

  @override
  Future<Me> update({String? timezone, String? currency}) async {
    patches.add({'timezone': timezone, 'currency': currency});
    me = Me(
      id: me.id,
      email: me.email,
      timezone: timezone ?? me.timezone,
      currency: currency ?? me.currency,
      effectiveCurrency: currency ?? me.currency ?? 'USD',
    );
    return me;
  }
}

// On start the app sends the device timezone when it changed and proposes a
// currency (from country, else zone) when none is chosen — once.
void main() {
  Future<ProviderContainer> container(_FakeMeApi api,
      {String? zone, String? country}) async {
    SharedPreferences.setMockInitialValues({'mindos.auth.access': 'a'});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      meApiProvider.overrideWithValue(api),
      deviceTimeZoneProvider.overrideWithValue(() async => zone),
      deviceCountryProvider.overrideWithValue(() => country),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  const fresh = Me(
    id: 'u',
    email: 'a@b.c',
    timezone: 'UTC',
    currency: null,
    effectiveCurrency: 'USD',
  );

  test('sends the device zone and a suggested currency for a new user', () async {
    final api = _FakeMeApi(fresh);
    final c = await container(api, zone: 'America/Sao_Paulo');

    final me = await c.read(meProvider.future);

    expect(api.patches, [
      {'timezone': 'America/Sao_Paulo', 'currency': 'BRL'},
    ]);
    expect(me.effectiveCurrency, 'BRL');
    expect(c.read(displayCurrencyProvider), 'BRL');
  });

  test('does not touch settings that already match', () async {
    final api = _FakeMeApi(const Me(
      id: 'u',
      email: 'a@b.c',
      timezone: 'America/Mexico_City',
      currency: 'MXN',
      effectiveCurrency: 'MXN',
    ));
    final c = await container(api, zone: 'America/Mexico_City', country: 'MX');

    await c.read(meProvider.future);

    expect(api.patches, isEmpty);
  });

  test('never overrides a currency the user chose', () async {
    final api = _FakeMeApi(const Me(
      id: 'u',
      email: 'a@b.c',
      timezone: 'UTC',
      currency: 'USD',
      effectiveCurrency: 'USD',
    ));
    final c = await container(api, zone: 'America/Bogota', country: 'CO');

    await c.read(meProvider.future);

    expect(api.patches, [
      {'timezone': 'America/Bogota', 'currency': null},
    ]);
  });
}
