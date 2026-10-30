import { Router } from 'express';
import type { PoolClient } from 'pg';
import { db, withTransaction } from '../db.js';
import { requireAuth } from '../auth.js';
import { HttpError } from '../errors.js';
import { chargeCard } from '../services/paymentGateway.js';
import { releaseStock, reserveStock } from '../services/inventory.js';

export const ordersRouter = Router();

const STORE_CURRENCY = process.env.STORE_CURRENCY ?? 'USD';

export interface OrderRow {
  id: number;
  user_id: number;
  status: 'pending' | 'paid' | 'cancelled';
  total_cents: number;
  currency: string;
  charge_id: string | null;
  created_at: Date;
}

interface ItemInput {
  productId: number;
  quantity: number;
}

const ORDER_COLUMNS = 'id, user_id, status, total_cents, currency, charge_id, created_at';

function toOrderDto(row: OrderRow) {
  return { id: row.id, status: row.status, amountCents: row.total_cents, currency: row.currency, createdAt: row.created_at };
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
  const { rows: orders } = await db.query<OrderRow>(
    `SELECT ${ORDER_COLUMNS} FROM orders WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`,
    [req.user!.id],
  );
  const result = [];
  for (const order of orders) {
    const { rows: items } = await db.query(
      'SELECT product_id, quantity, unit_price_cents FROM order_items WHERE order_id = $1',
      [order.id],
    );
    result.push({ ...toOrderDto(order), items });
  }
  res.json(result);
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
    await reserveStock(client, items);
    const total = items.reduce((sum, item) => sum + prices.get(item.productId)! * item.quantity, 0);
    const { rows } = await client.query<OrderRow>(
      `INSERT INTO orders (user_id, status, total_cents, currency) VALUES ($1, 'pending', $2, $3) RETURNING ${ORDER_COLUMNS}`,
      [req.user!.id, total, STORE_CURRENCY],
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
    currency: order.currency,
    paymentMethodId: String(req.body?.paymentMethodId ?? ''),
  });
  await db.query("UPDATE orders SET status = 'paid', charge_id = $1 WHERE id = $2", [charge.id, order.id]);
  res.json(toOrderDto({ ...order, status: 'paid', charge_id: charge.id }));
});

ordersRouter.post('/:id/cancel', requireAuth, async (req, res) => {
  const orderId = Number(req.params.id);
  try {
    await withTransaction(async (client) => {
      const { rowCount } = await client.query(
        "UPDATE orders SET status = 'cancelled' WHERE id = $1 AND user_id = $2 AND status = 'pending'",
        [orderId, req.user!.id],
      );
      if (rowCount !== 1) {
        throw new HttpError(409, 'not_cancellable');
      }
      await releaseStock(client, orderId);
    });
  } catch (err) {
    console.warn('order cancel failed', { orderId, err });
  }
  res.json({ id: orderId, status: 'cancelled' });
});
