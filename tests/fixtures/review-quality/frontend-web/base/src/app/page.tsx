import { ProductCard } from '@/components/ProductCard';
import { getProducts } from '@/lib/api';

export default async function HomePage() {
  const products = await getProducts();
  return (
    <main>
      <h1>Shop</h1>
      <ul className="product-grid">
        {products.slice(0, 60).map((product) => (
          <li key={product.id}>
            <ProductCard product={product} />
          </li>
        ))}
      </ul>
    </main>
  );
}
