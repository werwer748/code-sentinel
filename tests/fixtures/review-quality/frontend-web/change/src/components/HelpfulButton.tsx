'use client';

import { useState } from 'react';

export function HelpfulButton({ reviewId, initialCount }: { reviewId: number; initialCount: number }) {
  const [count, setCount] = useState(initialCount);
  const [voted, setVoted] = useState(false);

  async function vote() {
    if (voted) return;
    setVoted(true);
    setCount((current) => current + 1);
    try {
      const res = await fetch(`/api/reviews/${reviewId}/helpful`, { method: 'POST' });
      if (!res.ok) {
        console.warn('helpful vote rejected', res.status);
      }
    } catch (err) {
      console.warn('helpful vote failed', err);
    }
  }

  return (
    <button type="button" className="helpful" onClick={vote} disabled={voted} aria-pressed={voted}>
      Helpful ({count})
    </button>
  );
}
