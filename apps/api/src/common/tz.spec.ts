import * as fc from 'fast-check';
import {
  isValidCurrency,
  isValidTimeZone,
  localDateKey,
  localDay,
  startOfLocalDayKey,
  zoneOffsetMs,
} from './tz';

/**
 * Timezone math (D-013): local day keys, DST-safe start-of-day and day windows
 * for the zones that matter to the LatAm-first user base, plus validation.
 */
describe('tz helpers', () => {
  it('validates IANA zones and ISO-4217 currencies', () => {
    expect(isValidTimeZone('America/Mexico_City')).toBe(true);
    expect(isValidTimeZone('UTC')).toBe(true);
    expect(isValidTimeZone('Mars/Olympus')).toBe(false);
    expect(isValidTimeZone('')).toBe(false);
    expect(isValidCurrency('BRL')).toBe(true);
    expect(isValidCurrency('MXN')).toBe(true);
    expect(isValidCurrency('usd')).toBe(false);
    expect(isValidCurrency('XXXX')).toBe(false);
  });

  it('computes the local calendar day, not the UTC one', () => {
    // 2026-07-11 02:00 UTC is still the 10th in Mexico City (UTC-6).
    const instant = new Date('2026-07-11T02:00:00.000Z');
    expect(localDateKey(instant, 'UTC')).toBe('2026-07-11');
    expect(localDateKey(instant, 'America/Mexico_City')).toBe('2026-07-10');
    expect(localDateKey(instant, 'America/Sao_Paulo')).toBe('2026-07-10');
    expect(localDateKey(instant, 'Asia/Tokyo')).toBe('2026-07-11');
  });

  it('knows the offset of a zone at an instant', () => {
    const instant = new Date('2026-07-10T12:00:00.000Z');
    expect(zoneOffsetMs(instant, 'America/Mexico_City')).toBe(-6 * 3600_000);
    expect(zoneOffsetMs(instant, 'America/Sao_Paulo')).toBe(-3 * 3600_000);
    expect(zoneOffsetMs(instant, 'UTC')).toBe(0);
  });

  it('starts the local day at local midnight (UTC instant)', () => {
    expect(
      startOfLocalDayKey('2026-07-10', 'America/Sao_Paulo').toISOString(),
    ).toBe('2026-07-10T03:00:00.000Z');
    expect(startOfLocalDayKey('2026-07-10', 'UTC').toISOString()).toBe(
      '2026-07-10T00:00:00.000Z',
    );
  });

  it('handles DST transitions (23h and 25h days)', () => {
    // US spring forward 2026-03-08 and fall back 2026-11-01 (New York).
    const spring = localDay(
      new Date('2026-03-08T12:00:00Z'),
      'America/New_York',
    );
    expect(spring.start.toISOString()).toBe('2026-03-08T05:00:00.000Z');
    expect(spring.end.getTime() - spring.start.getTime()).toBe(23 * 3600_000);
    const fall = localDay(new Date('2026-11-01T12:00:00Z'), 'America/New_York');
    expect(fall.end.getTime() - fall.start.getTime()).toBe(25 * 3600_000);
  });

  it('every instant falls inside its own local day window (property)', () => {
    const zones = [
      'UTC',
      'America/Mexico_City',
      'America/Sao_Paulo',
      'America/Bogota',
      'America/New_York',
      'Europe/Madrid',
      'Asia/Tokyo',
    ];
    fc.assert(
      fc.property(
        fc.integer({ min: Date.UTC(2025, 0, 1), max: Date.UTC(2028, 0, 1) }),
        fc.constantFrom(...zones),
        (ms, zone) => {
          const instant = new Date(ms);
          const day = localDay(instant, zone);
          expect(day.start.getTime()).toBeLessThanOrEqual(ms);
          expect(day.end.getTime()).toBeGreaterThan(ms);
          expect(localDateKey(day.start, zone)).toBe(day.key);
        },
      ),
    );
  });
});
