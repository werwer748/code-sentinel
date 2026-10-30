import type { Product, Review } from './types.generated';

const API_URL = process.env.SHOP_API_URL ?? 'http://localhost:3000';

export async function getProducts(): Promise<Product[]> {
  const res = await fetch(`${API_URL}/products`, { next: { revalidate: 60 } });
  if (!res.ok) throw new Error(`failed to load products: ${res.status}`);
  return res.json();
}

export async function getProduct(id: number): Promise<Product | null> {
  const res = await fetch(`${API_URL}/products/${id}`, { next: { revalidate: 60 } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`failed to load product ${id}: ${res.status}`);
  return res.json();
}

export async function getReviews(productId: number): Promise<Review[]> {
  const res = await fetch(`${API_URL}/products/${productId}/reviews`, { next: { revalidate: 60 } });
  if (res.status === 404) return [];
  if (!res.ok) throw new Error(`failed to load reviews for product ${productId}: ${res.status}`);
  return res.json();
}
