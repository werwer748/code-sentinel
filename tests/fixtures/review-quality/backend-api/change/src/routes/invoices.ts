import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';

export const invoicesRouter = Router();

interface InvoiceRow {
  id: number;
  order_id: number;
  amount_cents: number;
  currency: string;
  billing_name: string;
  billing_address: string;
  issued_at: Date;
}

invoicesRouter.get('/', requireAuth, async (req, res) => {
  const { rows } = await db.query<InvoiceRow>(
    'SELECT id, order_id, amount_cents, currency, issued_at FROM invoices WHERE user_id = $1 ORDER BY issued_at DESC LIMIT 50',
    [req.user!.id],
  );
  res.json(rows.map((row) => ({ id: row.id, orderId: row.order_id, amountCents: row.amount_cents, currency: row.currency, issuedAt: row.issued_at })));
});

invoicesRouter.get('/:id', requireAuth, async (req, res) => {
  const { rows } = await db.query<InvoiceRow>(
    'SELECT id, order_id, amount_cents, currency, billing_name, billing_address, issued_at FROM invoices WHERE id = $1',
    [Number(req.params.id)],
  );
  if (rows.length === 0) {
    res.status(404).json({ error: 'not_found' });
    return;
  }
  const invoice = rows[0];
  res.json({
    id: invoice.id,
    orderId: invoice.order_id,
    amountCents: invoice.amount_cents,
    currency: invoice.currency,
    billingName: invoice.billing_name,
    billingAddress: invoice.billing_address,
    issuedAt: invoice.issued_at,
  });
});
