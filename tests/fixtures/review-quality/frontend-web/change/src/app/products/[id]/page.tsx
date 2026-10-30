import DOMPurify from 'isomorphic-dompurify';
import { cookies } from 'next/headers';
import { notFound } from 'next/navigation';
import { AddToCart } from '@/components/AddToCart';
import { DealBanner } from '@/components/DealBanner';
import { PriceTag } from '@/components/PriceTag';
import { ProductGallery } from '@/components/ProductGallery';
import { ReviewList } from '@/components/ReviewList';
import { StockBadge } from '@/components/StockBadge';
import { getProduct, getReviews } from '@/lib/api';

export default async function ProductPage({ params }: { params: { id: string } }) {
  const id = Number(params.id);
  const [product, reviews] = await Promise.all([getProduct(id), getReviews(id)]);
  if (!product) notFound();
  const tier = cookies().get('member_tier')?.value ?? null;

  return (
    <main className="product">
      <ProductGallery images={product.images} name={product.name} />
      <h1>{product.name}</h1>
      {product.dealEndsAt && <DealBanner endsAt={product.dealEndsAt} />}
      <PriceTag productId={product.id} listPriceCents={product.priceCents} tier={tier} />
      <StockBadge productId={product.id} />
      <div
        className="description"
        dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(product.descriptionHtml) }}
      />
      <AddToCart productId={product.id} />
      <ReviewList reviews={reviews} />
    </main>
  );
}
