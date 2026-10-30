import Link from 'next/link';
import { formatPrice } from '@/lib/format';
import type { Product } from '@/lib/types.generated';

export function ProductCard({ product }: { product: Product }) {
  return (
    <article className="product-card">
      <Link href={`/products/${product.id}`}>{product.name}</Link>
      <p className="product-card-price">{formatPrice(product.priceCents)}</p>
    </article>
  );
}
