import Link from 'next/link';
import { formatPrice } from '@/lib/format';
import type { Product } from '@/lib/types.generated';

export function ProductCard({ product }: { product: Product }) {
  return (
    <article className="product-card">
      <Link href={`/products/${product.id}`}>{product.name}</Link>
      <p className="product-card-price">{formatPrice(product.priceCents)}</p>
      {product.reviewCount > 0 && (
        <p className="product-card-rating">
          Rated {product.rating.toFixed(1)} of 5 ({product.reviewCount} reviews)
        </p>
      )}
    </article>
  );
}
