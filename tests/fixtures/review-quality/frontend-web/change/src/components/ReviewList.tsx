import type { Review } from '@/lib/types.generated';
import { HelpfulButton } from './HelpfulButton';

export function ReviewList({ reviews }: { reviews: Review[] }) {
  if (reviews.length === 0) {
    return <p className="reviews-empty">No reviews yet.</p>;
  }
  return (
    <section className="reviews" aria-labelledby="reviews-heading">
      <h2 id="reviews-heading">Customer reviews</h2>
      <ul>
        {reviews.map((review) => (
          <li key={review.id} className="review">
            <p className="review-meta">
              {review.author} rated it {review.rating} of 5
            </p>
            <div className="review-body" dangerouslySetInnerHTML={{ __html: review.bodyHtml }} />
            <HelpfulButton reviewId={review.id} initialCount={review.helpfulCount} />
          </li>
        ))}
      </ul>
    </section>
  );
}
