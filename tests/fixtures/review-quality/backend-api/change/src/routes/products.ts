import { Router } from 'express';
import { db } from '../db.js';

export const productsRouter = Router();

productsRouter.get('/search', async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  if (q.length < 2) {
    res.status(400).json({ error: 'query_too_short' });
    return;
  }
  const params: unknown[] = [`%${q}%`];
  let sql = 'SELECT id, name, price_cents, category FROM products WHERE name ILIKE $1';
  if (typeof req.query.category === 'string' && req.query.category !== '') {
    params.push(req.query.category);
    sql += ` AND category = $${params.length}`;
  }
  if (req.query.maxPrice !== undefined) {
    const maxPrice = Number(req.query.maxPrice);
    if (!Number.isInteger(maxPrice) || maxPrice < 0) {
      res.status(400).json({ error: 'invalid_max_price' });
      return;
    }
    params.push(maxPrice);
    sql += ` AND price_cents <= $${params.length}`;
  }
  sql += ' ORDER BY name LIMIT 50';
  const { rows } = await db.query(sql, params);
  res.json(rows);
});

productsRouter.get('/by-category/:category', async (req, res) => {
  const { rows } = await db.query(
    `SELECT id, name, price_cents, category FROM products WHERE category = '${req.params.category}' ORDER BY name LIMIT 100`,
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
