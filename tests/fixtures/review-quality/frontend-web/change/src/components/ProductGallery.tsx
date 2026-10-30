'use client';

import { useState } from 'react';

export function ProductGallery({ images, name }: { images: string[]; name: string }) {
  const [active, setActive] = useState(0);
  if (images.length === 0) return null;
  const current = images[Math.min(active, images.length - 1)];

  return (
    <div className="gallery">
      {/* eslint-disable-next-line @next/next/no-img-element -- CDN serves pre-sized WebP; next/image would re-encode it (docs/adr/0004-product-images.md) */}
      <img src={current} alt={name} width={800} height={800} className="gallery-main" />
      <ul className="gallery-thumbs">
        {images.map((src, i) => (
          <li key={`${i}-${src}`}>
            <button
              type="button"
              onClick={() => setActive(i)}
              aria-label={`Show image ${i + 1} of ${images.length}`}
              aria-current={i === active}
            >
              {/* eslint-disable-next-line @next/next/no-img-element -- same CDN thumbnails, see docs/adr/0004-product-images.md */}
              <img src={`${src}?w=96`} alt="" width={96} height={96} />
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
