import { Router } from 'express';
import { db } from '../db.js';

export const productsRouter = Router();

productsRouter.get('/search', async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  if (q.length < 2) {
    res.status(400).json({ error: 'query_too_short' });
    return;
  }
  const { rows } = await db.query(
    'SELECT id, name, price_cents, category FROM products WHERE name ILIKE $1 ORDER BY name LIMIT 50',
    [`%${q}%`],
  );
  res.json(rows);
});

productsRouter.get('/:id', async (req, res) => {
  const { rows } = await db.query(
    'SELECT id, name, price_cents, category, stock FROM products WHERE id = $1',
    [Number(req.params.id)],
  );
  if (rows.length === 0) {
    res.status(404).json({ error: 'not_found' });
    return;
  }
  res.json(rows[0]);
});
