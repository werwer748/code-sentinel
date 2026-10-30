import { Router } from 'express';
import type { PoolClient } from 'pg';
import { db, withTransaction } from '../db.js';
import { requireAuth } from '../auth.js';
import { HttpError } from '../errors.js';
import { chargeCard } from '../services/paymentGateway.js';

export const ordersRouter = Router();

export interface OrderRow {
  id: number;
  user_id: number;
  status: 'pending' | 'paid' | 'cancelled';
  total_cents: number;
  charge_id: string | null;
  created_at: Date;
}

interface ItemInput {
  productId: number;
  quantity: number;
}

const ORDER_COLUMNS = 'id, user_id, status, total_cents, charge_id, created_at';

function toOrderDto(row: OrderRow) {
  return { id: row.id, status: row.status, totalCents: row.total_cents, createdAt: row.created_at };
}

function parseItems(raw: unknown): ItemInput[] {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 50) {
    throw new HttpError(400, 'invalid_items');
  }
  const items = raw.map((entry) => {
    const productId = Number(entry?.productId);
    const quantity = Number(entry?.quantity);
    if (!Number.isInteger(productId) || !Number.isInteger(quantity) || quantity < 1 || quantity > 100) {
      throw new HttpError(400, 'invalid_items');
    }
    return { productId, quantity };
  });
  if (new Set(items.map((item) => item.productId)).size !== items.length) {
    throw new HttpError(400, 'duplicate_items');
  }
  return items;
}

async function priceItems(client: PoolClient, items: ItemInput[]): Promise<Map<number, number>> {
  const { rows } = await client.query<{ id: number; price_cents: number }>(
    'SELECT id, price_cents FROM products WHERE id = ANY($1::int[])',
    [items.map((item) => item.productId)],
  );
  if (rows.length !== items.length) {
    throw new HttpError(400, 'unknown_product');
  }
  return new Map(rows.map((row) => [row.id, row.price_cents]));
}

export async function findOwnedOrder(orderId: number, userId: number): Promise<OrderRow | undefined> {
  const { rows } = await db.query<OrderRow>(
    `SELECT ${ORDER_COLUMNS} FROM orders WHERE id = $1 AND user_id = $2`,
    [orderId, userId],
  );
  return rows[0];
}

ordersRouter.get('/', requireAuth, async (req, res) => {
  const { rows } = await db.query<OrderRow>(
    `SELECT ${ORDER_COLUMNS} FROM orders WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`,
    [req.user!.id],
  );
  res.json(rows.map(toOrderDto));
});

ordersRouter.get('/:id', requireAuth, async (req, res) => {
  const order = await findOwnedOrder(Number(req.params.id), req.user!.id);
  if (!order) {
    res.status(404).json({ error: 'not_found' });
    return;
  }
  res.json(toOrderDto(order));
});

ordersRouter.post('/', requireAuth, async (req, res) => {
  const items = parseItems(req.body?.items);
  const order = await withTransaction(async (client) => {
    const prices = await priceItems(client, items);
    const total = items.reduce((sum, item) => sum + prices.get(item.productId)! * item.quantity, 0);
    const { rows } = await client.query<OrderRow>(
      `INSERT INTO orders (user_id, status, total_cents) VALUES ($1, 'pending', $2) RETURNING ${ORDER_COLUMNS}`,
      [req.user!.id, total],
    );
    for (const item of items) {
      await client.query(
        'INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents) VALUES ($1, $2, $3, $4)',
        [rows[0].id, item.productId, item.quantity, prices.get(item.productId)],
      );
    }
    return rows[0];
  });
  res.status(201).json(toOrderDto(order));
});

ordersRouter.post('/:id/pay', requireAuth, async (req, res) => {
  const order = await findOwnedOrder(Number(req.params.id), req.user!.id);
  if (!order) {
    res.status(404).json({ error: 'not_found' });
    return;
  }
  if (order.status !== 'pending') {
    res.status(409).json({ error: 'not_payable' });
    return;
  }
  const charge = await chargeCard({
    orderId: order.id,
    amountCents: order.total_cents,
    paymentMethodId: String(req.body?.paymentMethodId ?? ''),
  });
  await db.query("UPDATE orders SET status = 'paid', charge_id = $1 WHERE id = $2", [charge.id, order.id]);
  res.json(toOrderDto({ ...order, status: 'paid', charge_id: charge.id }));
});
