import type { Product } from './types.generated';

/** Maps every token prefix (2+ characters) to the positions of the products that contain it. */
export type SearchIndex = Map<string, Set<number>>;

function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length > 1);
}

export function buildSearchIndex(products: Product[]): SearchIndex {
  const index: SearchIndex = new Map();
  products.forEach((product, position) => {
    const text = `${product.name} ${product.category} ${product.description}`;
    for (const token of tokenize(text)) {
      for (let end = 2; end <= token.length; end++) {
        const prefix = token.slice(0, end);
        let positions = index.get(prefix);
        if (!positions) {
          positions = new Set();
          index.set(prefix, positions);
        }
        positions.add(position);
      }
    }
  });
  return index;
}

/** Returns the products that contain every query token (as a prefix), in catalog order. */
export function searchIndex(index: SearchIndex, products: Product[], query: string): Product[] {
  const tokens = tokenize(query);
  if (tokens.length === 0) return products;
  let matches: Set<number> | null = null;
  for (const token of tokens) {
    const positions = index.get(token) ?? new Set<number>();
    matches = matches === null ? new Set(positions) : new Set([...matches].filter((p) => positions.has(p)));
  }
  return [...(matches ?? [])].sort((a, b) => a - b).map((position) => products[position]);
}
