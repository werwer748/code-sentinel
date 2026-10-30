# @acme/list-utils

Small, dependency-free helpers shared by our Node services.

## formatMinorUnits(amount, currency, locale?)

Formats an integer amount of minor units (cents, pence, yen) for display.

```ts
formatMinorUnits(123456, 'USD'); // "$1,234.56"
```

## paginate(items, page, pageSize)

Returns one 1-based page of an array together with paging metadata. `pageSize` must be between 1 and
`MAX_PAGE_SIZE` (100). Asking for a page past the end returns an empty `items` array.

```ts
const { items, totalPages, hasNextPage } = paginate(orders, 2, 20);
```
