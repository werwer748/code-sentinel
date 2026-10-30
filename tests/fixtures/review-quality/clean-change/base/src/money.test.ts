import { describe, expect, it } from 'vitest';
import { formatMinorUnits } from './money.js';

describe('formatMinorUnits', () => {
  it('formats cents as dollars', () => {
    expect(formatMinorUnits(123456, 'USD')).toBe('$1,234.56');
  });

  it('does not divide zero-decimal currencies', () => {
    expect(formatMinorUnits(1500, 'JPY', 'en-US')).toBe('¥1,500');
  });

  it('rejects fractional amounts', () => {
    expect(() => formatMinorUnits(1.5, 'USD')).toThrow(RangeError);
  });
});
