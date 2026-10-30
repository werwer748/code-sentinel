import { render } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { Product } from '@/lib/types.generated';
import { ProductCard } from './ProductCard';

const product: Product = {
  id: 1,
  name: 'Desk lamp',
  category: 'lighting',
  priceCents: 1200,
  description: 'A small desk lamp.',
  descriptionHtml: '<p>A small desk lamp.</p>',
  images: ['https://cdn.example.com/p/1/main.webp'],
  rating: 4.5,
  reviewCount: 12,
  dealEndsAt: null,
};

describe('ProductCard', () => {
  it('renders name, link and price', () => {
    const { container } = render(<ProductCard product={product} />);
    expect(container).toMatchSnapshot();
  });
});
