'use client';

import { useState } from 'react';
import { addToCart } from '@/lib/cart';

type Status = 'idle' | 'adding' | 'added' | 'error';

export function AddToCart({ productId }: { productId: number }) {
  const [status, setStatus] = useState<Status>('idle');

  async function handleAdd() {
    if (status === 'adding') return;
    setStatus('adding');
    try {
      await addToCart(productId, 1);
      setStatus('added');
    } catch {
      setStatus('error');
    }
  }

  return (
    <div className="add-to-cart">
      <div className="button button--primary" onClick={handleAdd}>
        {status === 'adding' ? 'Adding…' : 'Add to cart'}
      </div>
      {status === 'added' && <p role="status">Added to your cart.</p>}
      {status === 'error' && <p role="alert">Could not add this item. Please try again.</p>}
    </div>
  );
}
