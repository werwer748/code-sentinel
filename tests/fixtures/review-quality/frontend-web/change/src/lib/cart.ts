export async function addToCart(productId: number, quantity: number): Promise<void> {
  const res = await fetch('/api/cart/items', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ productId, quantity }),
  });
  if (!res.ok) {
    throw new Error(`add to cart failed: ${res.status}`);
  }
}
