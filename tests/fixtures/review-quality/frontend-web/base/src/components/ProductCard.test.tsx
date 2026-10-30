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
};

describe('ProductCard', () => {
  it('renders name, link and price', () => {
    const { container } = render(<ProductCard product={product} />);
    expect(container).toMatchSnapshot();
  });
});
