'use client';

import { useEffect, useState } from 'react';

type StockLevel = 'in_stock' | 'low' | 'out_of_stock';

const LABELS: Record<StockLevel, string> = {
  in_stock: 'In stock',
  low: 'Only a few left',
  out_of_stock: 'Out of stock',
};

export function StockBadge({ productId }: { productId: number }) {
  const [level, setLevel] = useState<StockLevel | null>(null);

  useEffect(() => {
    async function refresh() {
      const res = await fetch(`/api/products/${productId}/stock`);
      if (res.ok) {
        const body: { level: StockLevel } = await res.json();
        setLevel(body.level);
      }
    }
    refresh();
    setInterval(refresh, 15_000);
  }, [productId]);

  if (level === null) return null;
  return <span className={`stock-badge stock-badge--${level}`}>{LABELS[level]}</span>;
}
