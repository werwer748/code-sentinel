/** Largest page size accepted by {@link paginate}. */
export const MAX_PAGE_SIZE = 100;

export interface Page<T> {
  items: T[];
  /** 1-based page number that was requested. */
  page: number;
  pageSize: number;
  totalItems: number;
  /** 0 when the list is empty. */
  totalPages: number;
  hasPreviousPage: boolean;
  hasNextPage: boolean;
}

/**
 * Returns one page of `items`. Pages are 1-based and the input array is not modified.
 *
 * A page past the end returns an empty `items` array instead of throwing, so callers can render an
 * empty state for stale links (`hasPreviousPage` stays true so they can navigate back).
 * A `page` or `pageSize` that is not a positive integer, or a `pageSize` above
 * {@link MAX_PAGE_SIZE}, throws a RangeError.
 */
export function paginate<T>(items: readonly T[], page: number, pageSize: number): Page<T> {
  if (!Number.isSafeInteger(page) || page < 1) {
    throw new RangeError(`page must be a positive integer, got ${page}`);
  }
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > MAX_PAGE_SIZE) {
    throw new RangeError(`pageSize must be an integer from 1 to ${MAX_PAGE_SIZE}, got ${pageSize}`);
  }

  const totalItems = items.length;
  const totalPages = Math.ceil(totalItems / pageSize);
  const start = (page - 1) * pageSize;

  return {
    items: items.slice(start, start + pageSize),
    page,
    pageSize,
    totalItems,
    totalPages,
    hasPreviousPage: page > 1,
    hasNextPage: page < totalPages,
  };
}
