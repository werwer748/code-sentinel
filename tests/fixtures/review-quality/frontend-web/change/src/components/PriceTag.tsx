'use client';

import { useEffect, useState } from 'react';
import { formatPrice } from '@/lib/format';
import { getMemberPrice } from '@/lib/server/pricing';

interface PriceTagProps {
  productId: number;
  listPriceCents: number;
  tier: string | null;
}

export function PriceTag({ productId, listPriceCents, tier }: PriceTagProps) {
  const [memberPriceCents, setMemberPriceCents] = useState<number | null>(null);

  useEffect(() => {
    if (!tier) return;
    let cancelled = false;
    getMemberPrice(productId, tier)
      .then((price) => {
        if (!cancelled && price) setMemberPriceCents(price.memberPriceCents);
      })
      .catch(() => {
        // Keep showing the list price when the member price is unavailable.
      });
    return () => {
      cancelled = true;
    };
  }, [productId, tier]);

  if (memberPriceCents === null) {
    return <p className="price">{formatPrice(listPriceCents)}</p>;
  }
  return (
    <p className="price">
      <s>{formatPrice(listPriceCents)}</s> <strong>{formatPrice(memberPriceCents)}</strong> member price
    </p>
  );
}
