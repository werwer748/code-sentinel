import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';
import { findOwnedOrder } from './orders.js';

export const walletRouter = Router();

/** Wallet balances are kept in the store currency only. */
const WALLET_CURRENCY = 'USD';

walletRouter.get('/', requireAuth, async (req, res) => {
  const { rows } = await db.query<{ balance_cents: number }>(
    'SELECT balance_cents FROM wallets WHERE user_id = $1',
    [req.user!.id],
  );
  res.json({ balanceCents: rows[0]?.balance_cents ?? 0, currency: WALLET_CURRENCY });
});

walletRouter.post('/pay', requireAuth, async (req, res) => {
  const orderId = Number(req.body?.orderId);
  if (!Number.isInteger(orderId)) {
    res.status(400).json({ error: 'invalid_order_id' });
    return;
  }
  const order = await findOwnedOrder(orderId, req.user!.id);
  if (!order) {
    res.status(404).json({ error: 'not_found' });
    return;
  }
  if (order.status !== 'pending' || order.currency !== WALLET_CURRENCY) {
    res.status(409).json({ error: 'not_payable' });
    return;
  }

  const { rows } = await db.query<{ balance_cents: number }>(
    'SELECT balance_cents FROM wallets WHERE user_id = $1',
    [req.user!.id],
  );
  const balance = rows[0]?.balance_cents ?? 0;
  if (balance < order.total_cents) {
    res.status(402).json({ error: 'insufficient_balance', balanceCents: balance });
    return;
  }
  const newBalance = balance - order.total_cents;
  await db.query('UPDATE wallets SET balance_cents = $1, updated_at = now() WHERE user_id = $2', [newBalance, req.user!.id]);
  await db.query("UPDATE orders SET status = 'paid' WHERE id = $1", [order.id]);

  res.json({ orderId: order.id, status: 'paid', balanceCents: newBalance });
});
