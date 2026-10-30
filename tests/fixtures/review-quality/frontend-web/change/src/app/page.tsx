import { CatalogSearch } from '@/components/CatalogSearch';
import { getProducts } from '@/lib/api';

export default async function HomePage() {
  // The whole catalog (about 4,000 products) is sent once so that search runs on the client without round trips.
  const products = await getProducts();
  return (
    <main>
      <h1>Shop</h1>
      <CatalogSearch products={products} />
    </main>
  );
}
