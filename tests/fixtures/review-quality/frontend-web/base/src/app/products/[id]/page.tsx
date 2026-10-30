import { cookies } from 'next/headers';
import { notFound } from 'next/navigation';
import { getProduct } from '@/lib/api';
import { formatPrice } from '@/lib/format';
import { getMemberPrice } from '@/lib/server/pricing';

export default async function ProductPage({ params }: { params: { id: string } }) {
  const product = await getProduct(Number(params.id));
  if (!product) notFound();
  const tier = cookies().get('member_tier')?.value;
  const memberPrice = tier ? await getMemberPrice(product.id, tier) : null;

  return (
    <main className="product">
      <h1>{product.name}</h1>
      <p className="price">{formatPrice(memberPrice?.memberPriceCents ?? product.priceCents)}</p>
      <p className="description">{product.description}</p>
    </main>
  );
}
