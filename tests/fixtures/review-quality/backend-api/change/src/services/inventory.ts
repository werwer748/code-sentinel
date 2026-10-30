import type { PoolClient } from 'pg';
import { HttpError } from '../errors.js';

export interface StockRequest {
  productId: number;
  quantity: number;
}

/**
 * Decrements stock for the requested products inside the caller's transaction.
 * Rows are locked in ascending id order so concurrent orders cannot deadlock on each other.
 */
export async function reserveStock(client: PoolClient, items: StockRequest[]): Promise<void> {
  const wanted = new Map<number, number>();
  for (const item of items) {
    wanted.set(item.productId, (wanted.get(item.productId) ?? 0) + item.quantity);
  }
  const ids = [...wanted.keys()].sort((a, b) => a - b);

  const { rows } = await client.query<{ id: number; stock: number }>(
    'SELECT id, stock FROM products WHERE id = ANY($1::int[]) ORDER BY id FOR UPDATE',
    [ids],
  );
  const available = new Map(rows.map((row) => [row.id, row.stock]));
  for (const id of ids) {
    const stock = available.get(id);
    if (stock === undefined) {
      throw new HttpError(400, 'unknown_product');
    }
    if (stock < wanted.get(id)!) {
      throw new HttpError(409, 'insufficient_stock');
    }
  }

  await client.query(
    'UPDATE products AS p SET stock = p.stock - r.quantity FROM unnest($1::int[], $2::int[]) AS r(id, quantity) WHERE p.id = r.id',
    [ids, ids.map((id) => wanted.get(id)!)],
  );
}

/** Puts the stock of a cancelled order back. Must run in the same transaction as the status change. */
export async function releaseStock(client: PoolClient, orderId: number): Promise<void> {
  await client.query(
    'UPDATE products AS p SET stock = p.stock + oi.quantity FROM order_items AS oi WHERE oi.order_id = $1 AND oi.product_id = p.id',
    [orderId],
  );
}
