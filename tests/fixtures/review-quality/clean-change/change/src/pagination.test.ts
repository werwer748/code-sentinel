import { describe, expect, it } from 'vitest';
import { MAX_PAGE_SIZE, paginate } from './pagination.js';

const letters = ['a', 'b', 'c', 'd', 'e'];

describe('paginate', () => {
  it('returns the requested page with navigation flags', () => {
    expect(paginate(letters, 2, 2)).toEqual({
      items: ['c', 'd'],
      page: 2,
      pageSize: 2,
      totalItems: 5,
      totalPages: 3,
      hasPreviousPage: true,
      hasNextPage: true,
    });
  });

  it('returns a short last page', () => {
    const result = paginate(letters, 3, 2);
    expect(result.items).toEqual(['e']);
    expect(result.hasNextPage).toBe(false);
  });

  it('returns an empty page past the end instead of throwing', () => {
    const result = paginate(letters, 4, 2);
    expect(result.items).toEqual([]);
    expect(result.totalPages).toBe(3);
    expect(result.hasPreviousPage).toBe(true);
    expect(result.hasNextPage).toBe(false);
  });

  it('handles an empty list', () => {
    expect(paginate([], 1, 10)).toEqual({
      items: [],
      page: 1,
      pageSize: 10,
      totalItems: 0,
      totalPages: 0,
      hasPreviousPage: false,
      hasNextPage: false,
    });
  });

  it('does not modify the input array', () => {
    const input = [1, 2, 3];
    const result = paginate(input, 1, 2);
    result.items.push(99);
    expect(input).toEqual([1, 2, 3]);
  });

  it('accepts the maximum page size', () => {
    expect(paginate(letters, 1, MAX_PAGE_SIZE).items).toEqual(letters);
  });

  it.each([0, -1, 1.5, Number.NaN, Number.POSITIVE_INFINITY])('rejects page %s', (page) => {
    expect(() => paginate(letters, page, 2)).toThrow(RangeError);
  });

  it.each([0, -3, 2.5, MAX_PAGE_SIZE + 1, Number.NaN])('rejects pageSize %s', (pageSize) => {
    expect(() => paginate(letters, 1, pageSize)).toThrow(RangeError);
  });
});
