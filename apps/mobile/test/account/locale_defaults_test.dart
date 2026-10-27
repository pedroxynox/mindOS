import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/account/locale_defaults.dart';

// Currency defaults for a LatAm-first audience (D-014) and the dependency-free
// money formatter.
void main() {
  group('suggestCurrency', () {
    test('prefers the device country', () {
      expect(suggestCurrency(countryCode: 'BR'), 'BRL');
      expect(suggestCurrency(countryCode: 'mx'), 'MXN');
    });

    test('falls back to the timezone when the browser has no country', () {
      expect(suggestCurrency(timeZone: 'America/Bogota'), 'COP');
      expect(suggestCurrency(timeZone: 'America/Argentina/Cordoba'), 'ARS');
    });

    test('defaults to USD when nothing is known', () {
      expect(suggestCurrency(), 'USD');
      expect(suggestCurrency(countryCode: 'ZZ', timeZone: 'Etc/Unknown'), 'USD');
    });
  });

  group('formatMoney', () {
    test('uses the Latin-American convention', () {
      expect(formatMoney(1234.5, 'BRL'), r'R$ 1.234,50');
      expect(formatMoney(98, 'MXN'), r'$ 98,00');
    });

    test('drops decimals for zero-decimal currencies', () {
      expect(formatMoney(1234567.4, 'COP'), r'$ 1.234.567');
      expect(formatMoney(15000, 'CLP'), r'$ 15.000');
    });

    test('uses the US convention for USD and handles negatives', () {
      expect(formatMoney(1234.5, 'USD'), r'US$ 1,234.50');
      expect(formatMoney(-3, 'EUR'), '-€ 3,00');
    });
  });
}
