# @acme/list-utils

Small, dependency-free helpers shared by our Node services.

## formatMinorUnits(amount, currency, locale?)

Formats an integer amount of minor units (cents, pence, yen) for display.

```ts
formatMinorUnits(123456, 'USD'); // "$1,234.56"
```
