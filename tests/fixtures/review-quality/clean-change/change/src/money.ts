/**
 * Formats an integer amount of minor units (for example cents) for display.
 * The number of fraction digits comes from the currency, so JPY amounts are not divided.
 */
export function formatMinorUnits(amount: number, currency: string, locale = 'en-US'): string {
  if (!Number.isSafeInteger(amount)) {
    throw new RangeError(`amount must be a safe integer, got ${amount}`);
  }
  const formatter = new Intl.NumberFormat(locale, { style: 'currency', currency });
  const digits = formatter.resolvedOptions().maximumFractionDigits ?? 2;
  return formatter.format(amount / 10 ** digits);
}
