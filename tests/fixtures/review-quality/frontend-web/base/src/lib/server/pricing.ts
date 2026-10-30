// Member prices come from the internal pricing service. The service token is a server-side secret.
const PRICING_URL = process.env.PRICING_SERVICE_URL ?? 'http://pricing.internal:8080';
const PRICING_TOKEN = process.env.PRICING_SERVICE_TOKEN ?? '';

export interface MemberPrice {
  productId: number;
  memberPriceCents: number;
}

export async function getMemberPrice(productId: number, tier: string): Promise<MemberPrice | null> {
  const res = await fetch(`${PRICING_URL}/v2/prices/${productId}?tier=${encodeURIComponent(tier)}`, {
    headers: { authorization: `Bearer ${PRICING_TOKEN}` },
    cache: 'no-store',
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`pricing service responded ${res.status}`);
  return res.json();
}
