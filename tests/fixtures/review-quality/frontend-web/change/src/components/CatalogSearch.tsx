'use client';

import { useState } from 'react';
import { buildSearchIndex, searchIndex } from '@/lib/search';
import type { Product } from '@/lib/types.generated';
import { ProductCard } from './ProductCard';

const PAGE_SIZE = 60;

export function CatalogSearch({ products }: { products: Product[] }) {
  const [query, setQuery] = useState('');
  const index = buildSearchIndex(products);
  const results = query.trim() === '' ? products : searchIndex(index, products, query);
  const visible = results.slice(0, PAGE_SIZE);

  return (
    <section className="catalog">
      <input
        type="search"
        className="catalog-search"
        placeholder="Search products"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
      />
      <p className="catalog-count" aria-live="polite">
        Showing {visible.length} of {results.length} products
      </p>
      <ul className="product-grid">
        {visible.map((product) => (
          <li key={product.id}>
            <ProductCard product={product} />
          </li>
        ))}
      </ul>
    </section>
  );
}
